import Foundation

/// The log that the playback-log patch writes to iPod_Control/iTunes/iPodFirmPlaybackLog: the shuffle,
/// the playback and the failed memory allocations. Refer to patches/playback-log/playback_log.c.
///
/// The format is plain text. The first `infoSize` bytes are the information block. It starts with
/// "PL01" and has the line "list <JSON>", the iPodFirm list of the build (`FirmwareManifest`). Spaces
/// fill the rest of the block. The log lines follow. Zero bytes fill the rest of the file.
public enum PlaybackLog {
    /// The size of the file that the action "Clear the Playback Log" makes. The patch can only write to an existing file.
    public static let fileSize = 32768
    static let infoSize = 2048

    /// The text of the log, or nil if the file has no log. An empty file (only zero bytes) gives nil.
    /// `letters` gives the version letter of each patch name. The line "list <JSON>" becomes the line
    /// "patches: <letters>" and one line for each patch. `songs` has the tracks of the iTunesDB on the
    /// iPod: a line with "song=<ID>" gets the title and the artist (the ID is the low part of the dbid), and a list at the end has the album
    /// and the file of each song in the log.
    public static func text(_ data: [UInt8], letters: [String: String] = [:], songs: [ITunesDB.TrackInfo] = []) -> String? {
        let end = data.firstIndex(of: 0) ?? data.count
        guard end >= 4, data[0..<4] == [0x50, 0x4C, 0x30, 0x31] else { return nil }   // "PL01"
        var out: [String] = []
        for raw in String(decoding: data[0..<end], as: UTF8.self).split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("list ") {
                out += patchLines(String(line.dropFirst(5)), letters: letters)
            } else {
                out.append(line)
            }
        }
        return addSongs(out, songs: songs).joined(separator: "\n")
    }

    /// The track IDs in a log line: after "song=", "current=" and "first=". The value 0 is no song.
    static func songIDs(_ line: String) -> [UInt32] {
        var ids: [UInt32] = []
        for field in line.split(separator: " ") {
            guard let eq = field.firstIndex(of: "="), ["song", "current", "first"].contains(String(field[..<eq])) else { continue }
            ids += field[field.index(after: eq)...].split(separator: ",").compactMap { UInt32($0, radix: 16) }.filter { $0 != 0 }
        }
        return ids
    }

    static func addSongs(_ lines: [String], songs: [ITunesDB.TrackInfo]) -> [String] {
        guard !songs.isEmpty else { return lines }
        var byID: [UInt32: ITunesDB.TrackInfo] = [:]
        for s in songs { byID[s.dbidLow] = s }
        var order: [UInt32] = []
        var out = lines.map { line -> String in
            let ids = isTimed(Substring(line)) || line.hasPrefix(" ") ? songIDs(line) : []
            for id in ids where !order.contains(id) { order.append(id) }
            guard let id = ids.first, ids.count == 1 else { return line }
            guard let s = byID[id] else { return "\(line) (ID \(String(id, radix: 16)) is not in the iTunesDB)" }
            return "\(line) \"\(s.title)\" - \(s.artist)"
        }
        guard !order.isEmpty else { return out }
        out += ["", "Songs in this log (from the iTunesDB on the iPod. A sync after the test can change them):"]
        for id in order {
            let hex = String(id, radix: 16)
            if let s = byID[id] {
                out.append("  ID \(hex): \(s.title) | \(s.artist) | \(s.album) | \(s.path)")
            } else {
                out.append("  ID \(hex) is not in the iTunesDB")
            }
        }
        return out
    }

    /// The name of the text file that "Save the Log to Share…" makes, for example
    /// "iPodFirm Playback Log 2026-10-29 2315.txt".
    public static func fileName(date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HHmm"
        return "iPodFirm Playback Log \(f.string(from: date)).txt"
    }

    /// The largest body of the new issue. A longer web address can fail.
    static let maxIssueBody = 1500

    /// A web page that opens a new issue on GitHub. The body has the app version and the information
    /// lines of the log (the lines before the first line with a time). The owner of the log attaches
    /// the text file in the browser, because a web address cannot carry a file.
    public static func issueURL(log: String, appVersion: String, fileName: String) -> URL {
        let info = log.split(separator: "\n").prefix { !isTimed($0) }.joined(separator: "\n")
        let head = """
            The music stops. The playback log is attached.

            Drag the file "\(fileName)" into this box.

            iPodFirm on the Mac: \(appVersion)

            ```
            """
        let tail = "\n```\n"
        let room = max(0, maxIssueBody - head.count - tail.count - 1)
        let body = head + "\n" + String(info.prefix(room)) + tail
        var c = URLComponents(url: UpdateCheck.repository.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "title", value: "Playback log: the music stops"),
                        URLQueryItem(name: "body", value: body)]
        return c.url!
    }

    /// True for a log line: it starts with the time, for example "12.345 ".
    static func isTimed(_ line: Substring) -> Bool {
        guard let space = line.firstIndex(of: " ") else { return false }
        let t = line[..<space].split(separator: ".", omittingEmptySubsequences: false)
        return t.count == 2 && t[1].count == 3 && t.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    /// The patches of the iPodFirm list, with their letters.
    static func patchLines(_ json: String, letters: [String: String]) -> [String] {
        guard let list = try? JSONDecoder().decode(FirmwareManifest.self, from: Data(json.utf8)) else {
            return ["patches: not known (\(json))"]
        }
        let all = list.patches.compactMap { letters[$0.name] }.sorted().joined()
        var lines = ["app: \(list.app)", "patches: \(list.patches.count), letters \(all.isEmpty ? "none" : all)"]
        for p in list.patches {
            let options = (p.options ?? [:]).sorted { $0.key < $1.key }.map { " \($0.key)=\($0.value)" }.joined()
            lines.append("  \(letters[p.name] ?? "-") \(p.name)" + (p.version.map { " \($0)" } ?? "") + options)
        }
        return lines
    }
}
