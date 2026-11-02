import XCTest
@testable import IPodFWKit

/// A test on a real iPod. It opens the disk and reads, and it has no write call. macOS asks for the
/// password. Set IPODFW_AUTHOPEN_DISK, for example to disk15.
final class AuthOpenHardwareTests: XCTestCase {
    func testOpenWithOneAuthorization() throws {
        guard let disk = ProcessInfo.processInfo.environment["IPODFW_AUTHOPEN_DISK"] else { throw XCTSkip("set IPODFW_AUTHOPEN_DISK") }
        setbuf(stdout, nil)
        print("AUTHOPEN start")
        let whole = "/dev/r\(disk)", slice = whole + "s2"
        let auth = AuthOpen()
        func timed<T>(_ name: String, _ body: () throws -> T) rethrows -> T {
            let start = Date()
            defer { print("AUTHOPEN \(name): \(String(format: "%.1f", Date().timeIntervalSince(start))) s") }
            return try body()
        }
        try timed("authorize") { try auth.authorize(paths: [whole, slice], writable: false, prompt: "iPodFirm test: read the iPod.") }
        try timed("authorize write") { try auth.authorize(paths: [whole, slice], writable: true, prompt: "iPodFirm test: open the iPod.") }
        let reader = try RawDisk(descriptor: auth.open(path: whole, writable: false), blockSize: 2048)
        let located = try FirmwareFlasher.locatePartition(reader)
        let ipod = IPodDisk(disk: disk, mediaName: "iPod", blockSize: 2048, size: 0, volumeName: nil)
        print("AUTHOPEN partition:", located, "slice:", try Device.firmwareSlice(ipod, start: located.start) ?? "none")
        for i in 1...2 {
            let fd = try timed("read open \(i)") { try auth.open(path: whole, writable: false) }
            var block = [UInt8](repeating: 0, count: 2048)
            print("AUTHOPEN read \(i):", pread(fd, &block, 2048, 0), block[0], block[1])
            close(fd)
        }
        let fd = try timed("slice rw open") { try auth.open(path: slice, writable: true) }
        print("AUTHOPEN slice rw mode:", fcntl(fd, F_GETFL) & O_ACCMODE)
        close(fd)
        do {
            let whole = try timed("whole rw open") { try auth.open(path: whole, writable: true) }
            print("AUTHOPEN whole rw open passed"); close(whole)
        } catch { print("AUTHOPEN whole rw fault:", error.localizedDescription) }
    }
}
