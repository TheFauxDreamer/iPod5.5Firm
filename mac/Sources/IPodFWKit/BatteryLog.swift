import Foundation

/// The text of the file that the patch battery-log writes.
public enum BatteryLog {
    /// The file has zeros after the text. A clear from the Mac can also leave zeros in the text.
    public static func text(_ data: Data) -> String {
        String(decoding: data.filter { $0 != 0 }, as: UTF8.self)
    }
}
