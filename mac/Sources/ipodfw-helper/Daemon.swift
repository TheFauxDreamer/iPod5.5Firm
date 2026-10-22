import Foundation
import IPodFWKit

/// launchd daemon mode: serves HelperXPCProtocol to the signed iPodFirm app only, then exits when idle.
final class HelperService: NSObject, HelperXPCProtocol {
    let uid: uid_t

    init(uid: uid_t) { self.uid = uid }

    /// Backups may only be written inside the calling user's ~/Library/Application Support/iPodFirm.
    func checkedBackupDir(_ path: String) throws -> URL {
        guard let pw = getpwuid(uid) else { throw FirmwareError("Unknown user \(uid).") }
        let allowed = URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
            .appendingPathComponent("Library/Application Support/iPodFirm").standardizedFileURL.path
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.path.hasPrefix(allowed + "/") else { throw FirmwareError("Refusing to write backups outside \(allowed).") }
        return url
    }

    func ipod(_ disk: String) throws -> IPodDisk {
        guard let i = try Device.findIPods().first(where: { $0.disk == disk }) else {
            throw FirmwareError("No iPod at /dev/\(disk). Is it still connected?")
        }
        return i
    }

    func respond(_ reply: (Data) -> Void, _ body: () throws -> HelperResult) {
        Idle.begin()
        defer { Idle.end() }
        do { reply(HelperJSON.encode(try body())) } catch {
            reply(HelperJSON.encode(HelperResult(ok: false, message: error.localizedDescription, code: (error as? FirmwareError)?.code)))
        }
    }

    func status(reply: @escaping (Data) -> Void) {
        reply(HelperJSON.encode(HelperStatus(version: helperProtocolVersion, hasFullDiskAccess: processHasFullDiskAccess())))
    }

    func backup(disk: String, backupDir: String, reply: @escaping (Data) -> Void) {
        respond(reply) { try Operations.backup(ipod(disk), to: checkedBackupDir(backupDir), owner: uid) }
    }

    func readOSOS(disk: String, dir: String, reply: @escaping (Data) -> Void) {
        respond(reply) { try Operations.readOSOS(ipod(disk), to: checkedBackupDir(dir), owner: uid) }
    }

    func flash(disk: String, image: String, backupDir: String, reason: String, dryRun: Bool, reply: @escaping (Data) -> Void) {
        respond(reply) {
            try Operations.flash(ipod(disk), image: URL(fileURLWithPath: image), backupDir: checkedBackupDir(backupDir),
                                 reason: reason, dryRun: dryRun, owner: uid)
        }
    }

    func rescueRestore(disk: String, image: String, backupDir: String, dryRun: Bool, reply: @escaping (Data) -> Void) {
        respond(reply) {
            try Operations.rescueRestore(ipod(disk), image: URL(fileURLWithPath: image), backupDir: checkedBackupDir(backupDir),
                                         dryRun: dryRun, owner: uid)
        }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let requirement: String

    init(requirement: String) { self.requirement = requirement }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
        c.setCodeSigningRequirement(requirement)   // only our signed app may talk to us
        c.exportedInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        c.exportedObject = HelperService(uid: c.effectiveUserIdentifier)
        c.resume()
        Idle.touch()
        return true
    }
}

/// Exit after a quiet minute; launchd starts us again on the next request (and picks up app updates).
enum Idle {
    static let lock = NSLock()
    static var active = 0
    static var last = Date()

    static func begin() { lock.lock(); active += 1; last = Date(); lock.unlock() }
    static func end() { lock.lock(); active -= 1; last = Date(); lock.unlock() }
    static func touch() { lock.lock(); last = Date(); lock.unlock() }

    static func start() {
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            lock.lock(); defer { lock.unlock() }
            if active == 0 && Date().timeIntervalSince(last) > 60 { exit(0) }
        }
    }
}

func runDaemon() -> Never {
    guard let team = ownTeamIdentifier() else {
        FileHandle.standardError.write(Data("ipodfw-helper: not signed with a team identity; refusing to run as a daemon\n".utf8))
        exit(1)
    }
    let delegate = ListenerDelegate(requirement: signingRequirement(identifier: appBundleIdentifier, team: team))
    let listener = NSXPCListener(machServiceName: helperMachService)
    listener.delegate = delegate
    listener.resume()
    Idle.start()
    RunLoop.main.run()
    exit(0)
}
