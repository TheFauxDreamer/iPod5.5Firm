import Foundation

/// A curve from a battery log: the raw battery value at each percentage. The patch battery-display
/// uses it for Custom Battery. The percentage is the part of the play time that remained.
public struct BatteryCurve: Codable, Hashable {
    /// The count of points in the patch variables `curve_raw` and `curve_pct`.
    public static let points = 16
    static let minimumSamples = 30
    static let minimumFall = 60
    static let window = 3

    /// The raw values. They decrease from the first point to the last point.
    public var raw: [Int]
    /// The percentages. They decrease from 100 to 0.
    public var percent: [Int]
    /// The play time of the log, in hours.
    public var hours: Double

    /// One sample of the log: the seconds and the raw value.
    typealias Sample = (seconds: Int, raw: Int)

    /// Makes a curve from the text of a battery log. The longest run of the log gives the curve.
    /// The run starts at its highest value, so that time on a charger at the start has no effect.
    public static func make(log: String) throws -> BatteryCurve {
        var runs: [[Sample]] = [[]]
        for line in log.split(whereSeparator: \.isNewline) {
            if line == "start" { runs.append([]); continue }
            let fields = line.split(separator: " ")
            guard fields.count == 4, let seconds = Int(fields[0]), let raw = Int(fields[1]) else { continue }
            runs[runs.count - 1].append((seconds, raw))
        }
        guard let longest = runs.max(by: { ($0.last?.seconds ?? 0) < ($1.last?.seconds ?? 0) }),
              longest.count >= minimumSamples else {
            throw PatchError("The log has too few samples. Use a log from a full charge until the iPod stops.")
        }
        let smooth = longest.indices.map { i -> Int in
            let part = longest[max(0, i - window)...min(longest.count - 1, i + window)]
            return part.reduce(0) { $0 + $1.raw } / part.count
        }
        let first = smooth.indices.max { smooth[$0] < smooth[$1] } ?? 0
        let start = longest[first].seconds, end = longest[longest.count - 1].seconds
        guard end > start, smooth[first] - longest[longest.count - 1].raw >= minimumFall else {
            throw PatchError("The battery value did not fall enough. Use a log from a full charge until the iPod stops.")
        }
        var raw: [Int] = [], percent: [Int] = []
        for i in 0..<points {
            let time = start + (end - start) * i / (points - 1)
            let sample = (first..<longest.count).first { longest[$0].seconds >= time } ?? longest.count - 1
            var value = i == points - 1 ? longest[longest.count - 1].raw : smooth[sample]
            if let last = raw.last { value = min(value, last - 1) }
            raw.append(value)
            percent.append(100 - (100 * i + (points - 1) / 2) / (points - 1))
        }
        guard raw[points - 1] > 0 else {
            throw PatchError("The battery values of the log are not valid.")
        }
        return BatteryCurve(raw: raw, percent: percent, hours: Double(end - start) / 3600)
    }

    /// The two patch variables, as little-endian 16-bit values.
    var bytes: (raw: [UInt8], percent: [UInt8]) {
        func data(_ values: [Int]) -> [UInt8] { values.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] } }
        return (data(raw), data(percent))
    }
}
