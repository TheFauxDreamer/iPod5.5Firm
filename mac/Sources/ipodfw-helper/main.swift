import Foundation
import IPodFWKit

// Privileged helper. Two modes:
//   --daemon : launchd daemon (SMAppService) serving XPC to the signed app; the app does the Touch ID check
//   CLI      : run via "do shell script ... with administrator privileges" (password fallback)
//   ipodfw-helper backup --disk diskN --backup-dir DIR [--owner UID]
//   ipodfw-helper read   --disk diskN --backup-dir DIR [--owner UID]   (read only: DIR/ipod-osos.bin)
//   ipodfw-helper flash  --disk diskN --image FILE --backup-dir DIR --reason TEXT [--dry-run] [--owner UID]
//   ipodfw-helper rescue --disk diskN --image FILE --backup-dir DIR [--dry-run] [--owner UID]
// Prints one HelperResult JSON object on stdout.

func emit(_ r: HelperResult) -> Never {
    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601
    FileHandle.standardOutput.write((try? enc.encode(r)) ?? Data("{\"ok\":false,\"message\":\"encode failed\"}".utf8))
    exit(0)   // "do shell script" only returns stdout on success; ok=false carries errors
}

// The helper runs as root: it must not write the log file in the home folder of the user. The steps
// stay in memory and go back to the app in HelperResult.detail.
AppLog.directory = nil
if CommandLine.arguments.contains("--daemon") { runDaemon() }

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { emit(HelperResult(ok: false, message: "usage: ipodfw-helper backup|read|flash|rescue ...")) }
args.removeFirst()
var opts: [String: String] = [:]
var flags: Set<String> = []
var i = 0
while i < args.count {
    if args[i] == "--dry-run" { flags.insert("dry-run"); i += 1; continue }
    guard i + 1 < args.count else { emit(HelperResult(ok: false, message: "missing value for \(args[i])")) }
    opts[String(args[i].dropFirst(2))] = args[i + 1]
    i += 2
}

do {
    guard getuid() == 0 || geteuid() == 0 else { throw FirmwareError("ipodfw-helper must run as root.") }
    guard let diskID = opts["disk"], let dir = opts["backup-dir"] else { throw FirmwareError("--disk and --backup-dir are required.") }
    guard let ipod = try Device.findIPods().first(where: { $0.disk == diskID }) else {
        throw FirmwareError("No iPod at /dev/\(diskID). Is it still connected?")
    }
    let owner = opts["owner"].flatMap { uid_t($0) }
    let backupDir = URL(fileURLWithPath: dir)
    switch command {
    case "backup":
        emit(try Operations.backup(ipod, to: backupDir, owner: owner))
    case "read":
        emit(try Operations.readOSOS(ipod, to: backupDir, owner: owner))
    case "flash":
        guard let image = opts["image"] else { throw FirmwareError("--image is required.") }
        emit(try Operations.flash(ipod, image: URL(fileURLWithPath: image), backupDir: backupDir,
                                  reason: opts["reason"] ?? "flash", dryRun: flags.contains("dry-run"), owner: owner))
    case "rescue":
        guard let image = opts["image"] else { throw FirmwareError("--image is required.") }
        emit(try Operations.rescueRestore(ipod, image: URL(fileURLWithPath: image), backupDir: backupDir,
                                          dryRun: flags.contains("dry-run"), owner: owner))
    default:
        throw FirmwareError("unknown command \(command)")
    }
} catch {
    emit(HelperResult(failure: error))
}
