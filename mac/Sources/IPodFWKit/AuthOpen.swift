import Foundation
import Security

/// Opens a raw disk through the Apple program `authopen`. No code of iPodFirm runs as root: macOS asks
/// for the name and the password of an administrator, `authopen` opens the disk, and the app gets the
/// file descriptor. One authorization is kept, so that macOS can accept the password for a short time
/// (the right `sys.openfile.` has a timeout of 300 seconds).
public final class AuthOpen: @unchecked Sendable {
    public static let shared = AuthOpen()

    private let lock = NSLock()
    private var authorization: AuthorizationRef?

    public init() {}

    deinit { if let authorization { AuthorizationFree(authorization, []) } }

    /// The right that `authopen` asks for.
    static func right(path: String, writable: Bool) -> String {
        "sys.openfile.\(writable ? "readwrite" : "readonly").\(path)"
    }

    private func reference() throws -> AuthorizationRef {
        if let authorization { return authorization }
        var made: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, [], &made)
        guard status == errAuthorizationSuccess, let made else { throw Self.error(status) }
        authorization = made
        return made
    }

    static func error(_ status: OSStatus) -> FirmwareError {
        if status == errAuthorizationCanceled { return FirmwareError("Cancelled.") }
        let text = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
        return FirmwareError("macOS did not give access to the iPod: \(text)")
    }

    /// Ask for the password now, for each path. This call blocks until the user replies. Call it before the
    /// iPod unmounts: if the user clicks Cancel, the iPod stays as it was.
    public func authorize(paths: [String], writable: Bool, prompt: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let ref = try reference()
        let names = paths.map { strdup(Self.right(path: $0, writable: writable))! }
        defer { names.forEach { free($0) } }
        var items = names.map { AuthorizationItem(name: UnsafePointer($0), valueLength: 0, value: nil, flags: 0) }
        let status = prompt.withCString { text -> OSStatus in
            var entry = AuthorizationItem(name: kAuthorizationEnvironmentPrompt, valueLength: strlen(text),
                                          value: UnsafeMutableRawPointer(mutating: text), flags: 0)
            return withUnsafeMutablePointer(to: &entry) { entryPointer in
                var environment = AuthorizationEnvironment(count: 1, items: entryPointer)
                return items.withUnsafeMutableBufferPointer { buffer in
                    var rights = AuthorizationRights(count: UInt32(buffer.count), items: buffer.baseAddress)
                    return AuthorizationCopyRights(ref, &rights, &environment, [.interactionAllowed, .extendRights, .preAuthorize], nil)
                }
            }
        }
        guard status == errAuthorizationSuccess else { throw Self.error(status) }
    }

    /// Open `path`, and give the file descriptor to the caller. Call `authorize` first.
    public func open(path: String, writable: Bool) throws -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        var external = AuthorizationExternalForm()
        let status = AuthorizationMakeExternalForm(try reference(), &external)
        guard status == errAuthorizationSuccess else { throw Self.error(status) }

        var sockets: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0 else {
            throw FirmwareError("Cannot make a socket: \(String(cString: strerror(errno)))")
        }
        defer { Darwin.close(sockets[0]) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/libexec/authopen")
        process.arguments = ["-stdoutpipe", "-extauth", "-o", String(writable ? O_RDWR : O_RDONLY), path]
        let input = Pipe(), problems = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle(fileDescriptor: sockets[1], closeOnDealloc: true)
        process.standardError = problems
        try process.run()
        input.fileHandleForWriting.write(withUnsafeBytes(of: &external) { Data($0) })
        try input.fileHandleForWriting.close()
        let received = Self.receiveDescriptor(from: sockets[0], whileOpen: process)
        process.waitUntilExit()
        if let fd = received.fd { return fd }
        let text = String(decoding: problems.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        // authopen sends two bytes on a fault. The last byte is the errno value.
        if received.lastByte == UInt8(EBUSY) { throw FirmwareError("\(path) is in use. Eject the iPod volume, then try again.") }
        if received.lastByte == UInt8(EPERM) {
            throw FirmwareError("macOS blocked access to \(path). Turn on Full Disk Access for iPodFirm, then try again.")
        }
        var fault = FirmwareError("Cannot open \(path) through authopen.")
        fault.cause = "authopen status \(process.terminationStatus), \(received.note), stderr: \(text)"
        throw fault
    }

    /// Receive one descriptor (SCM_RIGHTS). The parent end stays open, so read until the child stops.
    static func receiveDescriptor(from socket: Int32, whileOpen process: Process) -> (fd: Int32?, note: String, lastByte: UInt8?) {
        var data = [UInt8](repeating: 0, count: 64)
        // On Darwin, a control message has a header of 12 bytes: length, level and type.
        let headerSize = 12
        var control = [UInt8](repeating: 0, count: headerSize + MemoryLayout<Int32>.size + 16)
        var polled = pollfd(fd: socket, events: Int16(POLLIN), revents: 0)
        while process.isRunning || poll(&polled, 1, 0) > 0 {
            guard poll(&polled, 1, 200) > 0 else { continue }
            let count = data.count, room = control.count
            let (got, controlLength): (Int, Int) = data.withUnsafeMutableBytes { dataBytes in
                control.withUnsafeMutableBytes { controlBytes in
                    var vector = iovec(iov_base: dataBytes.baseAddress, iov_len: count)
                    return withUnsafeMutablePointer(to: &vector) { vectorPointer in
                        var message = msghdr()
                        message.msg_iov = vectorPointer
                        message.msg_iovlen = 1
                        message.msg_control = controlBytes.baseAddress
                        message.msg_controllen = socklen_t(room)
                        let got = recvmsg(socket, &message, 0)
                        return (got, Int(message.msg_controllen))
                    }
                }
            }
            if got < 0 && errno == EINTR { continue }
            if got <= 0 { break }
            let note = "\(got) data bytes: \(data.prefix(got).map { String(format: "%02x", $0) }.joined())"
            guard controlLength >= headerSize + MemoryLayout<Int32>.size else { return (nil, note, data[got - 1]) }
            let (level, type, fd): (Int32, Int32, Int32) = control.withUnsafeBytes {
                ($0.loadUnaligned(fromByteOffset: 4, as: Int32.self), $0.loadUnaligned(fromByteOffset: 8, as: Int32.self),
                 $0.loadUnaligned(fromByteOffset: headerSize, as: Int32.self))
            }
            guard level == SOL_SOCKET, type == SCM_RIGHTS else { return (nil, note, data[got - 1]) }
            return (fd, note, nil)
        }
        return (nil, "no message", nil)
    }
}
