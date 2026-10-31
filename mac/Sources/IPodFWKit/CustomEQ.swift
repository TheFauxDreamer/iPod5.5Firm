import Foundation

/// The coefficients of the patch custom-eq. `src/ipodfw/custom_eq.py` has the same code.
/// Refer to re/custom-eq.md for the format of a record.
public enum CustomEQ {
    public enum Kind: Int, CaseIterable, Identifiable, Sendable {
        case lowShelf = 0, peak = 1, highShelf = 2
        public var id: Int { rawValue }
        public var title: String {
            switch self {
            case .lowShelf: "Low Shelf"
            case .peak: "Peak"
            case .highShelf: "High Shelf"
            }
        }
    }

    /// One band. The gain is in tenths of a dB and Q is in hundredths, so that the values are options.
    public struct Band: Hashable, Sendable {
        public var kind: Kind
        public var frequency, gain, q: Int
        public init(kind: Kind, frequency: Int, gain: Int, q: Int) {
            self.kind = kind; self.frequency = frequency; self.gain = gain; self.q = q
        }
    }

    public static let bandCount = 5
    public static let rates = [44100.0, 48000.0]
    public static let gainLimit = 120
    public static let frequencyRange = 20...20000
    public static let qRange = 30...800
    public static let defaults = [Band(kind: .lowShelf, frequency: 60, gain: 0, q: 71),
                                  Band(kind: .peak, frequency: 230, gain: 0, q: 100),
                                  Band(kind: .peak, frequency: 910, gain: 0, q: 100),
                                  Band(kind: .peak, frequency: 3600, gain: 0, q: 100),
                                  Band(kind: .highShelf, frequency: 14000, gain: 0, q: 71)]
    static let grid = 512
    static let q24 = 16_777_216.0

    /// The 5 bands from the option values. A missing value uses the default.
    public static func bands(from values: [String: Int]) -> [Band] {
        defaults.enumerated().map { i, d in
            let n = i + 1
            return Band(kind: Kind(rawValue: values["band\(n)_type"] ?? d.kind.rawValue) ?? d.kind,
                        frequency: values["band\(n)_freq"] ?? d.frequency,
                        gain: values["band\(n)_gain"] ?? d.gain,
                        q: values["band\(n)_q"] ?? d.q)
        }
    }

    /// The option values of the bands.
    public static func values(of bands: [Band]) -> [String: Int] {
        var out = [String: Int]()
        for (i, b) in bands.enumerated() {
            let n = i + 1
            out["band\(n)_type"] = b.kind.rawValue
            out["band\(n)_freq"] = b.frequency
            out["band\(n)_gain"] = b.gain
            out["band\(n)_q"] = b.q
        }
        return out
    }

    static func check(_ b: Band) throws {
        guard frequencyRange.contains(b.frequency) else { throw PatchError("The frequency \(b.frequency) Hz is out of range.") }
        guard abs(b.gain) <= gainLimit else { throw PatchError("The gain of a band must be −12 to +12 dB.") }
        guard qRange.contains(b.q) else { throw PatchError("The Q of a band must be 0.3 to 8.") }
    }

    /// b0, b1, b2, a1, a2 (Audio EQ Cookbook, R. Bristow-Johnson), with a0 = 1.
    public static func biquad(_ band: Band, rate: Double) -> [Double] {
        let w = 2 * Double.pi * Double(band.frequency) / rate
        let cw = cos(w), sw = sin(w)
        let alpha = sw / (2 * Double(band.q) / 100)
        let a = pow(10, Double(band.gain) / 400)
        let c: [Double]
        if band.kind == .peak {
            c = [1 + alpha * a, -2 * cw, 1 - alpha * a, 1 + alpha / a, -2 * cw, 1 - alpha / a]
        } else {
            let root = 2 * a.squareRoot() * alpha
            let s = band.kind == .lowShelf ? 1.0 : -1.0
            c = [a * ((a + 1) - s * (a - 1) * cw + root),
                 2 * s * a * ((a - 1) - s * (a + 1) * cw),
                 a * ((a + 1) - s * (a - 1) * cw - root),
                 (a + 1) + s * (a - 1) * cw + root,
                 -2 * s * ((a - 1) + s * (a + 1) * cw),
                 (a + 1) + s * (a - 1) * cw - root]
        }
        return [c[0] / c[3], c[1] / c[3], c[2] / c[3], c[4] / c[3], c[5] / c[3]]
    }

    /// The gain of a chain of biquads in dB.
    public static func response(_ filters: [[Double]], frequency: Double, rate: Double) -> Double {
        let w = -2 * Double.pi * frequency / rate
        let zr = cos(w), zi = sin(w), z2r = cos(2 * w), z2i = sin(2 * w)
        var h = 1.0
        for f in filters {
            let nr = f[0] + f[1] * zr + f[2] * z2r, ni = f[1] * zi + f[2] * z2i
            let dr = 1 + f[3] * zr + f[4] * z2r, di = f[3] * zi + f[4] * z2i
            h *= ((nr * nr + ni * ni) / (dr * dr + di * di)).squareRoot()
        }
        return 20 * log10(max(h, 1e-9))
    }

    /// The highest gain in dB of a chain, from 20 Hz to 20 kHz.
    public static func peak(_ filters: [[Double]], rate: Double) -> Double {
        (0..<grid).map { response(filters, frequency: 20 * pow(1000, Double($0) / Double(grid - 1)), rate: rate) }.max() ?? 0
    }

    /// The level change in dB that keeps the highest point of the curve at 0 dB.
    public static func precut(_ bands: [Band], rate: Double = rates[0]) -> Double {
        let filters = bands.filter { $0.gain != 0 }.map { biquad($0, rate: rate) }
        return filters.isEmpty ? 0 : -max(peak(filters, rate: rate), 0)
    }

    /// The 200 bytes of custom_eq_records and the value of custom_eq_mask.
    public static func records(_ bands: [Band]) throws -> (data: [UInt8], mask: UInt32) {
        guard bands.count == bandCount else { throw PatchError("The EQ has \(bandCount) bands.") }
        var mask: UInt32 = 0, out = [Int32](repeating: 0, count: bandCount * 10)
        for b in bands { try check(b) }
        for (i, b) in bands.enumerated() where b.gain != 0 { mask |= 1 << UInt32(i) }
        for (r, rate) in rates.enumerated() {
            let cut = pow(10, precut(bands, rate: rate) / 20)
            var first = true
            for (i, b) in bands.enumerated() where b.gain != 0 {
                var f = biquad(b, rate: rate)
                if first {   // the precut: the numerator of the first active band
                    for k in 0..<3 { f[k] *= cut }
                    first = false
                }
                let q = f.map { ($0 * q24).rounded(.toNearestOrEven) }
                guard q[4] < q24, abs(q[3]) < q24 + q[4] else { throw PatchError("Band \(i + 1) is not stable.") }
                guard q.allSatisfy({ abs($0) < 0x7FFF_FFFE }) else { throw PatchError("Band \(i + 1) is out of range.") }
                for k in 0..<5 { out[i * 10 + r * 5 + k] = Int32(q[k]) }
            }
        }
        return (out.flatMap { v in (0..<4).map { UInt8(truncatingIfNeeded: v >> ($0 * 8)) } }, mask)
    }
}
