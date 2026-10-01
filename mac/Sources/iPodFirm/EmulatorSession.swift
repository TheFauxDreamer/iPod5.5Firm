import AppKit
import Foundation
import IPodFWKit

/// Runs the emulator hidden (`--headless --control=SOCKET`) and drives it from iPodFirm: the screen
/// is captured with the control socket's `shot` command, and buttons/wheel are sent the same way.
@MainActor
final class EmulatorSession: ObservableObject {
    enum Phase: Equatable { case stopped, preparing, booting(Double), running, failed(String) }

    @Published var phase: Phase = .stopped
    @Published var screen: NSImage?

    private var process: Process?
    private var pollTask: Task<Void, Never>?
    private let socketPath = "/tmp/ipodfirm-\(getuid()).sock"
    private let shotPath = FileManager.default.temporaryDirectory.appendingPathComponent("ipodfirm-screen.png").path

    var isActive: Bool {
        switch phase { case .booting, .running, .preparing: true; default: false }
    }

    func start(prepare: @escaping () async throws -> Void) {
        stop()
        phase = .preparing
        screen = nil
        Task {
            do {
                try await prepare()
                try launch()
                poll()
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func launch() throws {
        unlink(socketPath)
        let p = Process()
        p.executableURL = EmulatorManager.appURL.appendingPathComponent("Contents/MacOS/ipod-emulator")
        p.arguments = ["--headless=100000000000000", "--control=\(socketPath)"]
        var env = ProcessInfo.processInfo.environment
        env["IPOD_EMULATOR_DATA"] = EmulatorManager.profile.path
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                guard let self, self.process === proc else { return }
                self.process = nil
                self.pollTask?.cancel()
                if self.phase != .stopped { self.phase = .failed("The emulator stopped (exit \(proc.terminationStatus)).") }
            }
        }
        try p.run()
        process = p
        phase = .booting(0)
    }

    private func poll() {
        pollTask?.cancel()
        let sock = socketPath, shot = shotPath
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let state = await Self.send(sock, "state")
                guard let self, !Task.isCancelled else { return }
                if let state { self.update(from: state) }
                if await Self.send(sock, "shot \(shot)")?.hasPrefix("ok") == true,
                   let img = NSImage(contentsOfFile: shot) {
                    self.screen = img
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    private func update(from state: String) {
        if state.contains("phase=Running") {
            phase = .running
        } else if state.contains("phase=Booting"),
                  let exe = Self.number(after: "executed=", in: state),
                  let target = Self.number(after: "target: ", in: state), target > 0 {
            phase = .booting(min(1, exe / target))
        }
    }

    static func number(after key: String, in s: String) -> Double? {
        guard let r = s.range(of: key) else { return nil }
        return Double(s[r.upperBound...].prefix { $0.isNumber })
    }

    // MARK: controls

    enum Button: String { case select, menu, play, prev = "left", next = "right" }

    /// Measured on RetailOS 1.3 in the emulator: about six wheel detents move the highlight one row.
    static let detentsPerItem = 6

    func press(_ b: Button) { send("press \(b.rawValue)") }
    func wheel(_ detents: Int) { if detents != 0 { send("wheel \(detents)") } }

    private func send(_ command: String) {
        let sock = socketPath
        Task.detached { _ = await Self.send(sock, command) }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        phase = .stopped
        if let p = process, p.isRunning { p.terminate() }
        process = nil
    }

    /// One command per connection, one reply line back.
    nonisolated static func send(_ path: String, _ command: String) async -> String? {
        await Task.detached { () -> String? in
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { return nil }
            defer { close(fd) }
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let bytes = Array(path.utf8)
            guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
            withUnsafeMutableBytes(of: &addr.sun_path) { raw in
                raw.copyBytes(from: bytes)
                raw[bytes.count] = 0
            }
            let ok = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard ok == 0 else { return nil }
            var tv = timeval(tv_sec: 3, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            let line = Array((command + "\n").utf8)
            guard write(fd, line, line.count) == line.count else { return nil }
            var out = [UInt8]()
            var buf = [UInt8](repeating: 0, count: 4096)
            while !out.contains(10) {
                let n = read(fd, &buf, buf.count)
                if n <= 0 { break }
                out += buf[0..<n]
            }
            _ = write(fd, Array("quit\n".utf8), 5)
            return String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }
}
