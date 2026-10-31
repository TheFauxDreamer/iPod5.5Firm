import Foundation

/// The iPodFirm list: the patches, their versions and the appearance of a build. The build writes it
/// into osos after the extended data. No iPod code reads it. The app reads it from the iPod to show
/// which patches are on the iPod.
///
/// Format: the text `magic`, a 32-bit little-endian length, then the JSON text. The list starts on a
/// 16-byte step after the last patch, before the rounding of the image to 0x800 bytes.
public struct FirmwareManifest: Codable, Equatable {
    public struct Entry: Codable, Equatable {
        public var name: String
        public var version: String?
        /// The value of each option (patch.json "options"), if it is not empty.
        public var options: [String: Int]?
        /// The EQs of a patch with `eq_editor`, if the list is not empty.
        public var eqs: [NamedEQ]?
        public init(name: String, version: String?, options: [String: Int]? = nil, eqs: [NamedEQ]? = nil) {
            self.name = name; self.version = version; self.options = options; self.eqs = eqs
        }
    }

    /// The app version that made the build, for example "0.1.147 (148)".
    public var app: String
    public var patches: [Entry]
    /// "light", "dark" or "switch" (AppModel.Appearance).
    public var appearance: String?
    /// The name of the dark theme, if the appearance is not "light".
    public var theme: String?

    public init(app: String, patches: [Entry], appearance: String? = nil, theme: String? = nil) {
        self.app = app; self.patches = patches; self.appearance = appearance; self.theme = theme
    }

    public static let magic = Array("iPodFirmManifest1\0".utf8)
    /// The largest list that `read` accepts.
    static let maxLength = 64 * 1024

    /// The bytes that the build writes: the magic, the length and the JSON text.
    public func encoded() throws -> [UInt8] {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let json = [UInt8](try enc.encode(self))
        var length = [UInt8](repeating: 0, count: 4)
        put32(&length, 0, UInt32(json.count))
        return Self.magic + length + json
    }

    /// The list in `osos`, or nil if the image has no list. The search starts at the end, because the
    /// list is after all other data.
    public static func read(osos: [UInt8]) -> FirmwareManifest? {
        let start = Patcher.maxOSOSSize
        guard osos.count > start + magic.count + 4 else { return nil }
        var at = (osos.count - magic.count) & ~15
        while at >= start {
            if osos[at] == magic[0], osos[at..<at + magic.count].elementsEqual(magic) {
                let length = Int(le32(osos, at + magic.count)), json = at + magic.count + 4
                guard length <= maxLength, json + length <= osos.count else { return nil }
                return try? JSONDecoder().decode(FirmwareManifest.self, from: Data(osos[json..<json + length]))
            }
            at -= 16
        }
        return nil
    }
}

/// What the app knows about one patch in a firmware image.
public enum PatchDetection: Equatable {
    /// The patch is in the image. The version is known only from the iPodFirm list.
    case installed(version: String?)
    case absent
    /// The image has changes at the places of the patch, but the places are shared (`chain`) with other patches.
    case unknown
}

extension PatchDetection {
    /// The switches that agree with `detections`: installed patches on, absent patches off. A patch
    /// with `unknown` and a patch that is not in `known` keep their switch.
    public static func mirroredSwitches(current: Set<String>, detections: [String: PatchDetection],
                                        known: Set<String>) -> Set<String> {
        var out = current
        for (name, d) in detections where known.contains(name) {
            switch d {
            case .installed: out.insert(name)
            case .absent: out.remove(name)
            case .unknown: break
            }
        }
        return out
    }
}

extension Patcher {
    /// The patches of `patches` in the image `osos`. With an iPodFirm list, the list gives the result.
    /// Without a list, the result comes from the changed words:
    /// - each `bytes` entry has its `value`, and each hook without `chain` is not `expect`: installed;
    /// - a patch with only `chain` hooks and no `bytes`: unknown if all its hook places are changed;
    /// - else: absent.
    public static func detect(osos: [UInt8], patches: [PatchInfo]) -> [String: PatchDetection] {
        if let list = FirmwareManifest.read(osos: osos) {
            var out = [String: PatchDetection]()
            for p in patches { out[p.spec.name] = .absent }
            for e in list.patches { out[e.name] = .installed(version: e.version) }
            return out
        }
        var out = [String: PatchDetection]()
        for p in patches { out[p.spec.name] = detectByWords(osos: osos, spec: p.spec) }
        return out
    }

    static func detectByWords(osos: [UInt8], spec: PatchSpec) -> PatchDetection {
        var checks = [Bool]()                                  // true: the place has the change of the patch
        for b in spec.bytes ?? [] {
            guard let at = try? Int(hex(b.at)), let value = try? hexBytes(b.value), at + value.count <= osos.count else { return .absent }
            checks.append(osos[at..<at + value.count].elementsEqual(value))
        }
        var chained = [Bool]()
        for h in spec.hooks ?? [] {
            guard let at = try? Int(hex(h.at)), let expect = try? hex(h.expect), at + 4 <= osos.count else { return .absent }
            if h.chain == nil { checks.append(le32(osos, at) != expect) } else { chained.append(le32(osos, at) != expect) }
        }
        if !checks.isEmpty { return checks.allSatisfy { $0 } ? .installed(version: nil) : .absent }
        if !chained.isEmpty { return chained.allSatisfy { $0 } ? .unknown : .absent }
        return .unknown                                        // no hooks and no bytes: nothing to compare
    }
}
