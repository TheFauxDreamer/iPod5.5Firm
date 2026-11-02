import Foundation

/// Opens a raw disk through the Apple program `authopen`. No code of iPodFirm runs as root. `authopen`
/// asks for the right itself. It is signed by Apple, so macOS offers Touch ID, or a password if Touch ID
/// is not available. The app gets the file descriptor. macOS asks at each open, so this class keeps
/// the descriptors for a short time. Refer to re/privilege-analysis.md.
public final class AuthOpen: @unchecked Sendable {
    public static let shared = AuthOpen()

    private let lock = NSLock()
    private let keepTime: TimeInterval
    private let now: () -> Date
    private let opener: ((String, Bool) throws -> Int32)?
    private var keptRead: (path: String, fd: Int32, time: Date)?
    private var keptWrite: (path: String, fd: Int32)?

    /// `now` and `opener` are for the tests. `opener` replaces `authopen`.
    public init(keepTime: TimeInterval = 60, now: @escaping () -> Date = Date.init,
                opener: ((String, Bool) throws -> Int32)? = nil) {
        self.keepTime = keepTime
        self.now = now
        self.opener = opener
    }

    deinit { closeKept() }

    static func isCancel(_ error: Error) -> Bool { (error as? FirmwareError)?.message == "Cancelled." }

    /// A descriptor for a read of the disk. The caller closes it. The next reads in `keepTime` open no prompt.
    public func read(path: String, blockSize: Int) throws -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        if let kept = keptRead, kept.path == path, now().timeIntervalSince(kept.time) < keepTime,
           Self.canRead(kept.fd, blockSize: blockSize) {
            let copy = dup(kept.fd)
            if copy >= 0 { return copy }
        }
        closeRead()
        let fd = try openNow(path, writable: false)
        keptRead = (path, fd, now())
        DispatchQueue.global().asyncAfter(deadline: .now() + keepTime + 1) { [weak self] in self?.closeExpired() }
        let copy = dup(fd)
        guard copy >= 0 else { throw FirmwareError("Cannot read \(path): \(String(cString: strerror(errno)))") }
        return copy
    }

    /// A kept descriptor stops at a disconnect, so a different iPod on the same path never uses it.
    static func canRead(_ fd: Int32, blockSize: Int) -> Bool {
        var block = [UInt8](repeating: 0, count: blockSize)
        return pread(fd, &block, blockSize, 0) == blockSize
    }

    /// Open `path` for a write now, and keep the descriptor for `takeWrite`. Call this before the unmount:
    /// if the user clicks Cancel, the iPod stays as it was.
    public func prepareWrite(path: String) throws {
        lock.lock()
        defer { lock.unlock() }
        closeWrite()
        keptWrite = (path, try openNow(path, writable: true))
    }

    /// The descriptor of `prepareWrite`, or nil. The caller closes it.
    public func takeWrite(path: String) -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        guard let kept = keptWrite, kept.path == path else { return nil }
        keptWrite = nil
        return kept.fd
    }

    /// Stop the read descriptor. A kept descriptor on the whole disk can stop an eject.
    public func closeKeptRead() {
        lock.lock()
        defer { lock.unlock() }
        closeRead()
    }

    /// Stop the write descriptor if the operation did not use it.
    public func closeKeptWrite() {
        lock.lock()
        defer { lock.unlock() }
        closeWrite()
    }

    public func closeKept() {
        closeKeptRead()
        closeKeptWrite()
    }

    private func closeExpired() {
        lock.lock()
        defer { lock.unlock() }
        if let kept = keptRead, now().timeIntervalSince(kept.time) >= keepTime { closeRead() }
    }

    private func closeRead() {
        if let kept = keptRead { Darwin.close(kept.fd) }
        keptRead = nil
    }

    private func closeWrite() {
        if let kept = keptWrite { Darwin.close(kept.fd) }
        keptWrite = nil
    }

    /// Open `path`, and give the file descriptor to the caller. macOS asks for Touch ID or a password.
    public func open(path: String, writable: Bool) throws -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        return try openNow(path, writable: writable)
    }

    private func openNow(_ path: String, writable: Bool) throws -> Int32 {
        if let opener { return try opener(path, writable) }
        var sockets: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0 else {
            throw FirmwareError("Cannot make a socket: \(String(cString: strerror(errno)))")
        }
        defer { Darwin.close(sockets[0]) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/libexec/authopen")
        process.arguments = ["-stdoutpipe", "-o", String(writable ? O_RDWR : O_RDONLY), path]
        let problems = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle(fileDescriptor: sockets[1], closeOnDealloc: true)
        process.standardError = problems
        try process.run()
        let received = Self.receiveDescriptor(from: sockets[0], whileOpen: process)
        process.waitUntilExit()
        if let fd = received.fd { return fd }
        let text = String(decoding: problems.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        // authopen sends two bytes on a fault. The last byte is the errno value.
        if let fault = Self.knownFault(received.lastByte, path: path) { throw fault }
        var fault = FirmwareError("Cannot open \(path) through authopen.")
        fault.cause = "authopen status \(process.terminationStatus), \(received.note), stderr: \(text)"
        throw fault
    }

    /// The fault for the errno value of `authopen`. A click on Cancel gives ECANCELED (measured on macOS 27.2).
    static func knownFault(_ byte: UInt8?, path: String) -> FirmwareError? {
        switch byte.map(Int32.init) {
        case ECANCELED: return FirmwareError("Cancelled.")
        case EBUSY: return FirmwareError("\(path) is in use. Eject the iPod volume, then try again.")
        case EPERM: return FirmwareError("macOS blocked access to \(path). Turn on Full Disk Access for iPodFirm, then try again.")
        default: return nil
        }
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
