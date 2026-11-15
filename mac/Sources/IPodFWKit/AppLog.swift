import Foundation
import os

/// An error that records the source location of its throw (FirmwareError, PatchError).
public protocol LocatedError: Error {
    var file: String { get }
    var line: Int { get }
    var function: String { get }
}

/// The log of iPodFirm. Each line goes to the file `~/Library/Logs/iPodFirm/iPodFirm.log` and to the
/// unified log of macOS (Console.app). The log has no home folder path and no user name (`redact`).
/// The user saves the log with Help > Save Log…, or from the alert of a fault.
/// With Help > Verbose Log, the log also gets the `debug` lines: each action of the user, each
/// change of the state, each external program, each open of the disk and each network request.
public enum AppLog {
    public enum Level: String { case debug = "DEBUG", info = "INFO", warning = "WARN", error = "ERROR" }

    /// The `UserDefaults` key of the verbose log.
    public static let verboseKey = "verboseLog"
    /// True: the log also gets the `debug` lines. Help > Verbose Log and the settings window set it.
    public static var verbose = UserDefaults.standard.bool(forKey: verboseKey) {
        didSet {
            guard verbose != oldValue else { return }
            UserDefaults.standard.set(verbose, forKey: verboseKey)
            write(.info, "Verbose log: \(verbose ? "on" : "off")")
        }
    }

    /// The folder of the log file. nil: no file, only the unified log. Only the app writes the file:
    /// the tests do not. The helper runs as root and sets nil, because it must not write in the home
    /// folder of the user.
    public static var directory: URL? = Bundle.main.bundleURL.pathExtension == "app"
        ? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Logs/iPodFirm")
        : nil
    /// At this size, the log file becomes the old file, and a new log file starts.
    public static var maxFileSize = 1_000_000
    /// The limit when the verbose log is on. A flash writes many verbose lines. With the 1 MB limit,
    /// the two files can lose the start of the operation.
    public static var verboseMaxFileSize = 5_000_000
    /// The limit that applies now.
    public static var fileLimit: Int { verbose ? verboseMaxFileSize : maxFileSize }
    /// The number of steps that the log keeps in memory for a fault report.
    static let maxSteps = 50

    static let queue = DispatchQueue(label: "iPodFirm.AppLog")
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.thefauxdreamer.ipodfirm", category: "app")
    private static var steps: [(date: Date, text: String)] = []

    /// The most recent log. A rotation starts a new file with this name.
    public static var fileURL: URL? { directory?.appendingPathComponent("iPodFirm.log") }
    static var oldFileURL: URL? { directory?.appendingPathComponent("iPodFirm.1.log") }

    /// The problem of the last folder check, or nil. Help > Open Log shows it.
    public private(set) static var directoryProblem: String?

    /// Makes the log folder at the launch, before the first line. A new installation has no folder.
    /// If a file has the name of the folder, or the user cannot write in the folder, the bad item gets
    /// a new name ("iPodFirm.old-…"). Then the app makes a new folder. The app deletes nothing.
    /// Returns true if the folder is ready.
    @discardableResult
    public static func prepareDirectory() -> Bool {
        guard let dir = directory else { return false }
        return queue.sync {
            let fm = FileManager.default
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: dir.path, isDirectory: &isDir)
            if exists, !(isDir.boolValue && fm.isWritableFile(atPath: dir.path)) {
                let aside = dir.deletingLastPathComponent()
                    .appendingPathComponent("\(dir.lastPathComponent).old-\(Int(Date().timeIntervalSince1970))")
                do {
                    try fm.moveItem(at: dir, to: aside)
                    logger.warning("The log folder was not usable. Its new name is \(aside.lastPathComponent, privacy: .public)")
                } catch {
                    directoryProblem = "The log folder \(redact(dir.path, volumes: [])) is not usable: \(error.localizedDescription)"
                    logger.error("\(directoryProblem!, privacy: .public)")
                    return false
                }
            }
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o755])
            } catch {
                directoryProblem = "Cannot make the log folder \(redact(dir.path, volumes: [])): \(error.localizedDescription)"
                logger.error("\(directoryProblem!, privacy: .public)")
                return false
            }
            directoryProblem = nil
            return true
        }
    }

    /// Records a detail for the verbose log. If the verbose log is off, the app does not make the text.
    public static func debug(_ text: @autoclosure () -> String) {
        if verbose { write(.debug, text()) }
    }
    /// Records an external program after its end: the name, the arguments, the exit status and the time.
    public static func debugProcess(_ process: Process, since start: Date) {
        debug("Program: \(process.executableURL?.lastPathComponent ?? "?") \((process.arguments ?? []).joined(separator: " "))"
              + " -> status \(process.terminationStatus), \(milliseconds(since: start)) ms")
    }
    /// The time from `start` to now, in milliseconds.
    public static func milliseconds(since start: Date) -> Int { Int(-start.timeIntervalSinceNow * 1000) }

    public static func info(_ text: String) { write(.info, text) }
    public static func warning(_ text: String) { write(.warning, text) }
    public static func error(_ text: String) { write(.error, text) }

    /// Records a step of an operation, for example "Build: apply patch shuffle-fixes 1.2". A fault
    /// report shows the last steps before the fault.
    public static func step(_ text: String) {
        let line = redact(text)
        queue.sync {
            steps.append((Date(), line))
            if steps.count > maxSteps { steps.removeFirst(steps.count - maxSteps) }
        }
        write(.info, "Step: " + line)
    }

    /// The last steps, the oldest first.
    public static func recentSteps(_ count: Int = 20) -> [String] { queue.sync { steps.suffix(count).map(\.text) } }
    /// The last step, if it is not older than `seconds`. An older step is possibly from a different operation.
    public static func lastStep(within seconds: TimeInterval = 120) -> String? {
        queue.sync { steps.last.flatMap { -$0.date.timeIntervalSinceNow <= seconds ? $0.text : nil } }
    }
    /// The helper daemon starts each request with no steps.
    public static func clearSteps() { queue.sync { steps.removeAll() } }

    static func write(_ level: Level, _ text: String) {
        let clean = redact(text)
        switch level {
        case .debug: logger.debug("\(clean, privacy: .public)")
        case .info: logger.info("\(clean, privacy: .public)")
        case .warning: logger.warning("\(clean, privacy: .public)")
        case .error: logger.error("\(clean, privacy: .public)")
        }
        guard let url = fileURL, let old = oldFileURL else { return }
        let line = "\(timestamp()) \(level.rawValue) \(clean)\n"
        queue.sync {
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size >= fileLimit {
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: url, to: old)
            }
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(Data(line.utf8))
                try? h.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }

    static func timestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    /// The names of the iPod volumes, for example "Alex's iPod". `redact` changes each name to "<volume>".
    /// The app sets the names after each search for iPods.
    public static var volumeNames: Set<String> {
        get { queue.sync { names } }
        set { queue.sync { names = newValue.filter { $0.count >= 2 } } }
    }
    private static var names: Set<String> = []

    /// Removes personal data from a text: a home folder path becomes "~", the short user name
    /// becomes "<user>", and the name of a volume becomes "<volume>".
    public static func redact(_ text: String, home: String = NSHomeDirectory(), user: String = NSUserName(),
                              volumes: Set<String>? = nil) -> String {
        var t = text
        // The longest name first: a name can contain a shorter name.
        for name in (volumes ?? volumeNames).sorted(by: { $0.count > $1.count }) {
            t = t.replacingOccurrences(of: name, with: "<volume>")
        }
        if home.count > 1 { t = t.replacingOccurrences(of: home, with: "~") }
        // "[s]" keeps the text "/Users/" out of the program. The release check of build-app.sh refuses that text.
        t = t.replacingOccurrences(of: #"/U[s]ers/[^/\s"']+"#, with: "~", options: .regularExpression)
        t = t.replacingOccurrences(of: #"/Volumes/[^/\n"]+"#, with: "/Volumes/<volume>", options: .regularExpression)
        if user.count >= 3, user != "root" {
            t = t.replacingOccurrences(of: "\\b" + NSRegularExpression.escapedPattern(for: user) + "\\b",
                                       with: "<user>", options: [.regularExpression, .caseInsensitive])
        }
        return t
    }

    /// The old log file and the current log file, the oldest line first.
    public static func fullText() -> String {
        queue.sync {
            [oldFileURL, fileURL].compactMap { $0.flatMap { try? String(contentsOf: $0, encoding: .utf8) } }.joined()
        }
    }

    /// The last lines of the log.
    public static func recentText(maxLines: Int) -> String {
        fullText().split(separator: "\n", omittingEmptySubsequences: false).suffix(maxLines + 1)
            .joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    /// All the data of an error: the Swift type, the FirmwareError code, source location, steps and
    /// cause, the NSError domain and code, and the chain of underlying errors.
    public static func describe(_ error: Error) -> String {
        var lines: [String] = []
        var current: Error? = error
        var depth = 0
        while let e = current, depth < 8 {
            let pad = String(repeating: "  ", count: depth)
            let prefix = depth == 0 ? "" : pad + "Caused by: "
            lines.append(prefix + "\(type(of: e)): \(e.localizedDescription)")
            if let le = e as? LocatedError { lines.append(pad + "  at: \(le.file):\(le.line) \(le.function)") }
            if let fe = e as? FirmwareError {
                if let code = fe.code { lines.append(pad + "  code: \(code)") }
                for c in fe.context { lines.append(pad + "  while: \(c)") }
                if let cause = fe.cause {
                    for l in cause.split(separator: "\n") { lines.append(pad + "  cause: \(l)") }
                }
                current = nil
            } else if e is LocatedError {
                current = nil
            } else {
                let ns = e as NSError
                var codeLine = pad + "  domain: \(ns.domain), code: \(ns.code)"
                if ns.domain == NSPOSIXErrorDomain, let s = strerror(Int32(ns.code)) { codeLine += " (\(String(cString: s)))" }
                lines.append(codeLine)
                if let path = ns.userInfo[NSFilePathErrorKey] as? String { lines.append(pad + "  file: \(path)") }
                current = ns.userInfo[NSUnderlyingErrorKey] as? Error
            }
            depth += 1
        }
        return redact(lines.joined(separator: "\n"))
    }

    /// The version of macOS and the model of the Mac, for a report.
    public static var systemDescription: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return "macOS \(ProcessInfo.processInfo.operatingSystemVersionString), \(String(cString: model))"
    }

    /// The first lines of the details of a fault and the first line of the last steps, each one short.
    /// A step can have many lines (a layout). The saved log has all of them.
    public static func faultExcerpt(details: String, steps: [String], lines: Int = 6, width: Int = 160) -> String {
        func short(_ s: Substring) -> String { String(s.prefix(width)) }
        let error = details.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix { !$0.isEmpty }.prefix(lines).map(short)
        let last = steps.compactMap { $0.split(separator: "\n").first }.map { "  " + short($0) }
        return (error + (last.isEmpty ? [] : ["Last steps:"] + last)).joined(separator: "\n")
    }

    /// The largest body of the new issue. A longer web address can fail.
    static let maxIssueBody = 1500

    /// A web page that opens a new issue on GitHub for a fault. The body has the fault, the details
    /// and the last steps. The user attaches the saved log file in the browser, because a web
    /// address cannot carry a file.
    public static func issueURL(title: String, message: String, details: String, fileName: String?) -> URL {
        let attach = fileName.map { "**Attach the log:** drag the file \"\($0)\" into this box." }
            ?? "**Attach the log:** select Help > Save Log… in iPodFirm. Then drag the file into this box."
        let head = """
            \(attach) We cannot find the fault without this file.

            What did you do before the fault?


            **Fault:** \(title)
            \(message)

            ```
            """
        let tail = "\n```\n"
        let room = max(0, maxIssueBody - head.count - tail.count - 1)
        // The saved log has the full data. The issue has only a short summary.
        let body = head + "\n" + String(redact(details).prefix(room)) + tail
        var c = URLComponents(url: UpdateCheck.repository.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "title", value: "Fault: \(title)"),
                        URLQueryItem(name: "body", value: redact(body))]
        return c.url!
    }

    /// The name of a saved log file, for example "iPodFirm Log 2026-10-29 1405.txt".
    public static func fileName(date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HHmm"
        return "iPodFirm Log \(f.string(from: date)).txt"
    }
}
