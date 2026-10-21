import Foundation

/// The log that the video-log patch writes to iPod_Control/iTunes/iPodFirmVideoLog: each command that
/// the firmware sends to the video processor, and each reply. The format is plain text. A header line
/// of 64 bytes starts with "VL01". One line follows for each record. Zero bytes fill the rest of the file.
/// Refer to patches/video-log/video_log.c.
public enum VideoLog {
    /// The size of the file that the action "Clear the Video Log" makes. The patch can only write to an existing file.
    public static let fileSize = 65536

    /// The text of the log, or nil if the file has no log. An empty file (only zero bytes) gives nil.
    public static func text(_ data: [UInt8]) -> String? {
        let end = data.firstIndex(of: 0) ?? data.count
        guard end >= 4, data[0..<4] == [0x56, 0x4C, 0x30, 0x31] else { return nil }   // "VL01"
        let text = String(decoding: data[0..<end], as: UTF8.self)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
    }
}
