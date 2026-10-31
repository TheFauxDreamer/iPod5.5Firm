import Foundation

/// The coefficients of the patch custom-eq. `src/ipodfw/custom_eq.py` has the same code.
/// Refer to re/custom-eq.md for the format of a record.
public enum CustomEQ {
    public enum Kind: Int, CaseIterable, Identifiable, Codable, Sendable {
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
    public struct Band: Hashable, Codable, Sendable {
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
    /// The fixed bands of the Simple view, with the name of each slider. The gain comes from the slider.
    public static let simpleNames = ["Bass", "Warmth", "Mids", "Clarity", "Treble"]
    public static let simpleLayout = [Band(kind: .lowShelf, frequency: 100, gain: 0, q: 71),
                                      Band(kind: .peak, frequency: 400, gain: 0, q: 80),
                                      Band(kind: .peak, frequency: 1000, gain: 0, q: 80),
                                      Band(kind: .peak, frequency: 3000, gain: 0, q: 80),
                                      Band(kind: .highShelf, frequency: 8000, gain: 0, q: 71)]
    /// 5 EQs with 5 bands use the filter numbers 55 to 79. 0x1446e8 accepts numbers to 96.
    public static let firstFilter = 55
    public static let maxEQs = 5
    static var maxFilters: Int { maxEQs * bandCount }
    public static let maxNameLength = 31
    static let entrySize = 70   // custom_eq in custom_eq.c

    /// custom_eq_records and custom_eq_list. Each active band of each EQ gets the next filter number.
    public static func library(_ eqs: [NamedEQ]) throws -> (records: [UInt8], list: [UInt8]) {
        guard eqs.count <= maxEQs else { throw PatchError("The iPod can have a maximum of \(maxEQs) EQs.") }
        var records = [UInt8](), list = [UInt8]()
        for eq in eqs {
            if let problem = nameProblem(eq.name, in: [], excluding: nil) { throw PatchError(problem) }
            let (data, mask) = try Self.records(eq.activeBands, precut: eq.preventClipping)
            var numbers = [UInt8](repeating: 0, count: bandCount)
            for i in 0..<bandCount where mask >> UInt32(i) & 1 == 1 {
                numbers[i] = UInt8(firstFilter + records.count / 40)
                records += data[i * 40..<(i + 1) * 40]
            }
            let name = Array(eq.name.utf16)
            var entry = [UInt8(truncatingIfNeeded: name.count), 0]
            for c in name + [UInt16](repeating: 0, count: maxNameLength - name.count) {
                entry += [UInt8(truncatingIfNeeded: c), UInt8(truncatingIfNeeded: c >> 8)]
            }
            list += entry + numbers + [0]
        }
        return (records + [UInt8](repeating: 0, count: maxFilters * 40 - records.count),
                list + [UInt8](repeating: 0, count: (maxEQs - eqs.count) * entrySize))
    }

    /// The reason that a name is not valid, or nil. The saved selection on the iPod is the name, so
    /// each name must be different. `excluding` is the present name in a rename.
    public static func nameProblem(_ name: String, in eqs: [NamedEQ], excluding: String?) -> String? {
        let key = name.lowercased()
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return "An EQ must have a name." }
        guard name == name.trimmingCharacters(in: .whitespaces) else { return "A name cannot start or end with a space." }
        guard name.utf16.count <= maxNameLength else { return "A name can have a maximum of \(maxNameLength) characters." }
        guard !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return "The name has a character that is not valid."
        }
        if key == "off" || applePresets.contains(where: { $0.name.lowercased() == key }) {
            return "The iPod already has an item with the name \"\(name)\"."
        }
        if key != excluding?.lowercased(), eqs.contains(where: { $0.name.lowercased() == key }) {
            return "You already have an EQ with the name \"\(name)\"."
        }
        return nil
    }

    /// true: the iPod font possibly cannot show the name, for example because it has an emoji.
    public static func nameCanFailToShow(_ name: String) -> Bool {
        name.unicodeScalars.contains { $0.value > 0xFFFF || $0.properties.isEmojiPresentation }
    }

    /// The start of `name` with a maximum of `limit` UTF-16 units. The iPod counts these units.
    public static func shortened(_ name: String, to limit: Int) -> String {
        var out = ""
        for c in name where out.utf16.count + c.utf16.count <= limit { out.append(c) }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// A name that no EQ has: `name`, or `name` with a number.
    public static func uniqueName(_ name: String, in eqs: [NamedEQ]) -> String {
        if nameProblem(name, in: eqs, excluding: nil) == nil { return name }
        let base = shortened(name, to: maxNameLength - 3)
        var n = 2
        while nameProblem("\(base) \(n)", in: eqs, excluding: nil) != nil { n += 1 }
        return "\(base) \(n)"
    }

    /// An Apple preset as bands of the editor.
    public struct Preset: Hashable, Identifiable, Sendable {
        public var name: String
        public var bands: [Band]
        public var id: String { name }
    }

    /// The bands that are nearest to the 22 Apple presets. re/fit-apple-presets.py measures them.
    /// Only the editor uses them. The largest difference from an Apple curve is in re/custom-eq.md.
    public static let applePresets = [
        Preset(name: "Acoustic", bands: [Band(kind: .lowShelf, frequency: 146, gain: 50, q: 71), Band(kind: .peak, frequency: 504, gain: 20, q: 128), Band(kind: .peak, frequency: 5245, gain: 40, q: 32)]),
        Preset(name: "Bass Booster", bands: [Band(kind: .lowShelf, frequency: 182, gain: 60, q: 50)]),
        Preset(name: "Bass Reducer", bands: [Band(kind: .lowShelf, frequency: 340, gain: -70, q: 52)]),
        Preset(name: "Classical", bands: [Band(kind: .lowShelf, frequency: 152, gain: 50, q: 38), Band(kind: .peak, frequency: 504, gain: -22, q: 40), Band(kind: .highShelf, frequency: 5043, gain: 40, q: 40)]),
        Preset(name: "Dance", bands: [Band(kind: .peak, frequency: 90, gain: 65, q: 75), Band(kind: .peak, frequency: 1812, gain: 40, q: 65), Band(kind: .peak, frequency: 5352, gain: 32, q: 52)]),
        Preset(name: "Deep", bands: [Band(kind: .lowShelf, frequency: 102, gain: 50, q: 58), Band(kind: .peak, frequency: 1403, gain: 30, q: 65), Band(kind: .highShelf, frequency: 4662, gain: -49, q: 48)]),
        Preset(name: "Electronic", bands: [Band(kind: .lowShelf, frequency: 102, gain: 50, q: 58), Band(kind: .peak, frequency: 504, gain: -30, q: 200), Band(kind: .highShelf, frequency: 6021, gain: 50, q: 58)]),
        Preset(name: "Flat", bands: []),
        Preset(name: "Hip Hop", bands: [Band(kind: .lowShelf, frequency: 200, gain: 50, q: 58), Band(kind: .peak, frequency: 762, gain: -21, q: 40), Band(kind: .highShelf, frequency: 11756, gain: 43, q: 50)]),
        Preset(name: "Jazz", bands: [Band(kind: .peak, frequency: 439, gain: 30, q: 42), Band(kind: .peak, frequency: 748, gain: -30, q: 42), Band(kind: .highShelf, frequency: 5043, gain: 40, q: 44)]),
        Preset(name: "Latin", bands: [Band(kind: .lowShelf, frequency: 69, gain: 51, q: 50), Band(kind: .peak, frequency: 1223, gain: -20, q: 42), Band(kind: .highShelf, frequency: 6910, gain: 49, q: 50)]),
        Preset(name: "Loudness", bands: [Band(kind: .lowShelf, frequency: 79, gain: 60, q: 71), Band(kind: .peak, frequency: 4062, gain: -60, q: 95), Band(kind: .peak, frequency: 7932, gain: 60, q: 95)]),
        Preset(name: "Lounge", bands: [Band(kind: .peak, frequency: 602, gain: 40, q: 65), Band(kind: .peak, frequency: 4062, gain: -40, q: 95), Band(kind: .peak, frequency: 9848, gain: 30, q: 42)]),
        Preset(name: "Piano", bands: [Band(kind: .lowShelf, frequency: 63, gain: 30, q: 71), Band(kind: .peak, frequency: 406, gain: 30, q: 75), Band(kind: .peak, frequency: 2000, gain: 40, q: 65)]),
        Preset(name: "Pop", bands: [Band(kind: .peak, frequency: 26, gain: -30, q: 40), Band(kind: .peak, frequency: 691, gain: 50, q: 42), Band(kind: .highShelf, frequency: 8249, gain: -31, q: 55)]),
        Preset(name: "R & B", bands: [Band(kind: .peak, frequency: 90, gain: 75, q: 65), Band(kind: .peak, frequency: 602, gain: -30, q: 75), Band(kind: .highShelf, frequency: 2296, gain: 39, q: 42)]),
        Preset(name: "Rock", bands: [Band(kind: .lowShelf, frequency: 130, gain: 50, q: 58), Band(kind: .peak, frequency: 892, gain: -20, q: 95), Band(kind: .highShelf, frequency: 4662, gain: 49, q: 48)]),
        Preset(name: "Small Speakers", bands: [Band(kind: .lowShelf, frequency: 200, gain: 30, q: 38), Band(kind: .highShelf, frequency: 3539, gain: -70, q: 38)]),
        Preset(name: "Spoken Word", bands: [Band(kind: .lowShelf, frequency: 52, gain: -40, q: 50), Band(kind: .peak, frequency: 1812, gain: 55, q: 30)]),
        Preset(name: "Treble Booster", bands: [Band(kind: .highShelf, frequency: 2484, gain: 60, q: 55)]),
        Preset(name: "Treble Reducer", bands: [Band(kind: .highShelf, frequency: 2080, gain: -70, q: 58)]),
        Preset(name: "Vocal Booster", bands: [Band(kind: .peak, frequency: 90, gain: -40, q: 55), Band(kind: .peak, frequency: 985, gain: 50, q: 42), Band(kind: .peak, frequency: 14034, gain: -30, q: 65)]),
    ]

    /// The range of gain, in tenths of a dB, that the Apple presets use. It is the default range of a band.
    public static let appleGainRange: ClosedRange<Int> = {
        let gains = applePresets.flatMap { $0.bands.map(\.gain) }
        return (gains.min() ?? 0)...(gains.max() ?? 0)
    }()
    public static let fullGainRange = -gainLimit...gainLimit
    /// The text that the user must agree to before a band can go past `appleGainRange`.
    public static let fullGainWarning = "Going higher than Apple's limits may negatively impact sound quality."

    /// The 5 bands of a preset. Its bands go into the standard positions, so they need no warning.
    public static func bands(forPreset preset: Preset) -> [Band] {
        var out = defaults
        for (i, band) in zip(standardBands, preset.bands) { out[i] = band }
        return out
    }

    /// true: the bands are flat or are exactly a preset. Thus a new preset loses no work of the user.
    public static func isUnedited(_ bands: [Band]) -> Bool {
        bands.allSatisfy { $0.gain == 0 } || applePresets.contains { Self.bands(forPreset: $0) == bands }
    }

    static let grid = 512
    static let q24 = 16_777_216.0

    /// The 3 bands that the user can edit by default. Apple presets use a maximum of 3 filters.
    public static let standardBands = [0, 2, 4]
    /// The text that the user must agree to before more than 3 bands can operate.
    public static let allBandsWarning = "Apple never uses more than 3 bands in one EQ. With all 5 bands, performance may be degraded. The music can have gaps."

    /// The option "all_bands": 1 means that the user agreed to `allBandsWarning`.
    public static func usesAllBands(_ values: [String: Int]) -> Bool { values["all_bands"] == 1 }

    /// The 5 bands from the option values. A missing value uses the default.
    /// Without the option "all_bands", the 2 other bands have no gain, so that they are off.
    public static func bands(from values: [String: Int]) -> [Band] {
        defaults.enumerated().map { i, d in
            let n = i + 1
            var gain = values["band\(n)_gain"] ?? d.gain
            if !usesAllBands(values), !standardBands.contains(i) { gain = 0 }
            return Band(kind: Kind(rawValue: values["band\(n)_type"] ?? d.kind.rawValue) ?? d.kind,
                        frequency: values["band\(n)_freq"] ?? d.frequency,
                        gain: gain,
                        q: values["band\(n)_q"] ?? d.q)
        }
    }

    /// The option "precut": 1 lowers the level by the highest boost. Apple presets do not do this.
    public static func usesPrecut(_ values: [String: Int]) -> Bool { values["precut"] == 1 }

    /// The option "advanced": 1 shows all the controls of each band. The default is the Simple view.
    public static func usesAdvanced(_ values: [String: Int]) -> Bool { values["advanced"] == 1 }

    /// The bands of the Simple view, with the gains of `bands`.
    public static func simple(from bands: [Band]) -> [Band] {
        zip(simpleLayout, bands).map { layout, band in
            var b = layout
            b.gain = band.gain
            return b
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
        guard (-gainLimit...gainLimit).contains(b.gain) else { throw PatchError("The gain of a band must be −12 to +12 dB.") }
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

    /// How much each band changes the sound at one frequency, in dB, with no sign. Only the curve
    /// of the editor uses this. A band at 0 dB gives 0.
    public static func bandWeights(_ bands: [Band], frequency: Double, rate: Double) -> [Double] {
        bands.map { $0.gain == 0 ? 0 : abs(response([biquad($0, rate: rate)], frequency: frequency, rate: rate)) }
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
    /// With `precut`, the numerator of the first active band lowers the level.
    public static func records(_ bands: [Band], precut usePrecut: Bool = false) throws -> (data: [UInt8], mask: UInt32) {
        guard bands.count == bandCount else { throw PatchError("The EQ has \(bandCount) bands.") }
        var mask: UInt32 = 0, out = [Int32](repeating: 0, count: bandCount * 10)
        for b in bands { try check(b) }
        for (i, b) in bands.enumerated() where b.gain != 0 { mask |= 1 << UInt32(i) }
        for (r, rate) in rates.enumerated() {
            let cut = usePrecut ? pow(10, precut(bands, rate: rate) / 20) : 1
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

/// A Custom EQ in a `.ipodeq` file, so that people can share it. The file is short JSON. It has no
/// user data. A received file is not trusted: `decode` examines all of it.
public struct SharedEQ: Codable, Equatable, Identifiable, Sendable {
    public struct Band: Codable, Equatable, Sendable {
        public var type: String
        public var frequency, gain, q: Int
    }

    public static let fileExtension = "ipodeq"
    public static let maxFileSize = 4096
    public static let maxNameLength = 64
    static let format = 1

    public var format: Int
    public var name: String
    public var bands: [Band]
    public var preventClipping: Bool
    public var view: String

    public var id: String { name }
    /// The app shows the Advanced view if the file has bands that the Simple view does not have.
    public var usesAdvanced: Bool { view == "advanced" || eqBands != CustomEQ.simple(from: eqBands) }

    /// The file has a band outside the range of the Apple presets.
    public var needsFullGain: Bool { eqBands.contains { !CustomEQ.appleGainRange.contains($0.gain) } }

    /// The file has a band that needs the option "all_bands".
    public var needsAllBands: Bool {
        eqBands.enumerated().contains { i, b in b.gain != 0 && !CustomEQ.standardBands.contains(i) }
    }

    /// The bands in the form of the editor. A band with an unknown type becomes a peak: `decode` rejects it first.
    public var eqBands: [CustomEQ.Band] {
        bands.map { CustomEQ.Band(kind: Self.kind($0.type) ?? .peak, frequency: $0.frequency, gain: $0.gain, q: $0.q) }
    }

    public init(name: String, bands: [CustomEQ.Band], preventClipping: Bool, advanced: Bool) {
        format = Self.format
        self.name = Self.clean(name)
        self.bands = bands.map { Band(type: Self.typeName($0.kind), frequency: $0.frequency, gain: $0.gain, q: $0.q) }
        self.preventClipping = preventClipping
        view = advanced ? "advanced" : "simple"
    }

    static func kind(_ name: String) -> CustomEQ.Kind? {
        switch name {
        case "lowShelf": .lowShelf
        case "peak": .peak
        case "highShelf": .highShelf
        default: nil
        }
    }

    static func typeName(_ kind: CustomEQ.Kind) -> String {
        switch kind {
        case .lowShelf: "lowShelf"
        case .peak: "peak"
        case .highShelf: "highShelf"
        }
    }

    /// Removes the control characters and limits the length. An empty name becomes "Custom EQ".
    static func clean(_ name: String) -> String {
        let text = String(String.UnicodeScalarView(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? "Custom EQ" : String(text.prefix(maxNameLength))
    }

    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// The EQ of a file. It throws if the file is not a valid EQ of this format.
    public static func decode(_ data: Data) throws -> SharedEQ {
        guard data.count <= maxFileSize else { throw PatchError("The file is too large for an EQ.") }
        guard var eq = try? JSONDecoder().decode(SharedEQ.self, from: data) else {
            throw PatchError("The file is not a Custom EQ file.")
        }
        guard eq.format == format else { throw PatchError("The EQ file has a different format. Update iPodFirm, then try again.") }
        guard eq.bands.count == CustomEQ.bandCount else { throw PatchError("An EQ file must have \(CustomEQ.bandCount) bands.") }
        guard eq.bands.allSatisfy({ kind($0.type) != nil }) else { throw PatchError("The EQ file has an unknown band type.") }
        guard ["simple", "advanced"].contains(eq.view) else { throw PatchError("The EQ file has an unknown view.") }
        _ = try CustomEQ.records(eq.eqBands, precut: eq.preventClipping)
        eq.name = clean(eq.name)
        return eq
    }
}

/// One EQ of the user. The app keeps a list of these. The name shows on the iPod.
public struct NamedEQ: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    public var bands: [CustomEQ.Band]
    public var preventClipping: Bool
    public var advanced: Bool
    /// The user agreed to `CustomEQ.allBandsWarning` for this EQ.
    public var allBands: Bool
    /// The user agreed to `CustomEQ.fullGainWarning` for this EQ. Older lists do not have this value.
    public var fullGain: Bool?

    public var id: String { name }

    /// The range of gain of each band of this EQ.
    public var gainRange: ClosedRange<Int> { fullGain == true ? CustomEQ.fullGainRange : CustomEQ.appleGainRange }

    /// The bands that the build uses: without `allBands`, only the standard bands have a gain.
    /// Without `fullGain`, each gain stays in the range of the Apple presets.
    public var activeBands: [CustomEQ.Band] {
        bands.enumerated().map { i, band in
            var b = band
            if !allBands, !CustomEQ.standardBands.contains(i) { b.gain = 0 }
            b.gain = min(max(b.gain, gainRange.lowerBound), gainRange.upperBound)
            return b
        }
    }

    public init(name: String, bands: [CustomEQ.Band] = CustomEQ.simpleLayout, preventClipping: Bool = false,
                advanced: Bool = false, allBands: Bool = false) {
        self.name = name; self.bands = bands; self.preventClipping = preventClipping
        self.advanced = advanced; self.allBands = allBands
    }

    /// The single EQ "Custom" of patch versions before 0.7, from the option values.
    public init(options values: [String: Int]) {
        self.init(name: "Custom", bands: CustomEQ.bands(from: values), preventClipping: CustomEQ.usesPrecut(values),
                  advanced: CustomEQ.usesAdvanced(values), allBands: CustomEQ.usesAllBands(values))
    }

    /// An EQ from a file, with a name that no other EQ has.
    public init(shared eq: SharedEQ, in eqs: [NamedEQ]) {
        self.init(name: CustomEQ.uniqueName(CustomEQ.shortened(eq.name, to: CustomEQ.maxNameLength), in: eqs), bands: eq.eqBands,
                  preventClipping: eq.preventClipping, advanced: eq.usesAdvanced, allBands: eq.needsAllBands)
        fullGain = eq.needsFullGain ? true : nil
    }
}
