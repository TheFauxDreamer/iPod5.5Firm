import CryptoKit
import Foundation

/// Editable view of a firmware file: pictures and strings in osos.
/// Every edit is applied straight to the partition with the osos checksum updated.
public final class FirmwareEditor {
    public let partition: FirmwarePartition
    public private(set) var osos: [UInt8]
    public private(set) var blocks: [ResourceBlock]
    public private(set) var mainIndex: Int
    public private(set) var pictures: [PictureItem]
    public let originalOSOSHash: String

    public init(partition: FirmwarePartition) throws {
        self.partition = partition
        osos = try partition.image("osos")
        originalOSOSHash = Self.sha256(osos)
        blocks = Resources.scan(osos, limit: partition.appleOSLength)
        let main = try Resources.mainBlock(blocks)
        mainIndex = main.index
        pictures = Pictures.list(osos, main)
    }

    public var mainBlock: ResourceBlock { blocks[mainIndex] }
    public var stringBlocks: [ResourceBlock] { blocks.filter { !$0.ofType("Str ").isEmpty } }

    static func sha256(_ b: [UInt8]) -> String { SHA256.hash(data: b).map { String(format: "%02x", $0) }.joined() }

    public func rgba(of item: PictureItem) -> [UInt8] { item.picture.decode(osos) }

    public func png(of item: PictureItem) -> Data? { ImageCodec.png(for: item.picture, osos: osos) }

    @discardableResult
    public func replacePicture(_ item: PictureItem, rgba: [UInt8]) throws -> Bool {
        var work = osos
        guard try item.picture.encode(&work, rgba: rgba) else { return false }
        try commit(work)
        return true
    }

    public func strings(_ block: ResourceBlock) -> [(key: String, value: String)] { Resources.readStrings(osos, block) }

    public func budget(_ block: ResourceBlock, _ values: [String: String]) -> (used: Int, available: Int) {
        Resources.stringBudget(osos, block, values)
    }

    @discardableResult
    public func setStrings(blockIndex: Int, _ values: [String: String]) throws -> Bool {
        var work = osos
        var block = blocks[blockIndex]
        guard try Resources.writeStrings(&work, &block, values) else { return false }
        try commit(work)
        blocks[blockIndex] = block
        return true
    }

    func commit(_ work: [UInt8]) throws {
        try partition.replaceImage("osos", with: work)
        osos = work
    }

    /// Take a new partition. The edits of the pictures and of the text stay.
    ///
    /// The function is for the repair of the partition, for example the restore of
    /// the hibernation image. The function changes the partition, not the osos.
    public func replacePartition(_ data: [UInt8]) throws {
        let new = try FirmwarePartition(data: data)
        partition.replace(with: new)
        osos = try new.image("osos")
    }

    // MARK: folder export / import (same layout as the Python `ipodfw unpack`)

    struct Manifest: Codable {
        struct Pic: Codable { var index: Int; var id: Int; var file: String; var format: String; var width: Int; var height: Int }
        struct Str: Codable { var block: Int; var file: String; var count: Int; var sample: String }
        var osos_sha256: String
        var model: String
        var pictures: [Pic]
        var string_blocks: [Str]
    }

    public func exportFolder(to dir: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appendingPathComponent("pictures"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("strings"), withIntermediateDirectories: true)
        var m = Manifest(osos_sha256: Self.sha256(osos), model: partition.model, pictures: [], string_blocks: [])
        for item in pictures {
            let name = String(format: "pictures/%04d_%d.png", item.index, item.resourceID)
            try png(of: item)?.write(to: dir.appendingPathComponent(name))
            m.pictures.append(.init(index: item.index, id: Int(item.resourceID), file: name, format: item.picture.formatName,
                                    width: item.picture.width, height: item.picture.height))
        }
        for block in stringBlocks {
            let pairs = strings(block)
            let name = String(format: "strings/block%02d_%@.json", block.index, block.index == mainIndex ? "main" : "lang")
            var json = "{\n"
            for (n, p) in pairs.enumerated() {
                let v = String(decoding: try JSONSerialization.data(withJSONObject: p.value, options: [.fragmentsAllowed, .withoutEscapingSlashes]), as: UTF8.self)
                json += " \"\(p.key)\": \(v)\(n < pairs.count - 1 ? "," : "")\n"
            }
            json += "}\n"
            try json.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
            m.string_blocks.append(.init(block: block.index, file: name, count: pairs.count,
                                         sample: pairs.first { $0.key == "129" }?.value ?? ""))
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try enc.encode(m).write(to: dir.appendingPathComponent("manifest.json"))
    }

    /// Apply a folder of edited PNGs / string JSON. Returns the files that changed something.
    public func importFolder(from dir: URL, force: Bool = false) throws -> [String] {
        let m = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: dir.appendingPathComponent("manifest.json")))
        guard force || m.osos_sha256 == originalOSOSHash || m.osos_sha256 == Self.sha256(osos) else {
            throw ResourceError("This folder was exported from a different firmware.")
        }
        var changed: [String] = []
        let byIndex = Dictionary(uniqueKeysWithValues: pictures.map { ($0.index, $0) })
        for p in m.pictures {
            let url = dir.appendingPathComponent(p.file)
            guard FileManager.default.fileExists(atPath: url.path), let item = byIndex[p.index] else { continue }
            let img = try ImageCodec.load(url)
            guard img.width == item.picture.width, img.height == item.picture.height else {
                throw PictureError("\(p.file) is \(img.width)×\(img.height); it must stay \(item.picture.width)×\(item.picture.height).")
            }
            if try replacePicture(item, rgba: ImageCodec.rgba(img)) { changed.append(p.file) }
        }
        for s in m.string_blocks {
            let url = dir.appendingPathComponent(s.file)
            guard FileManager.default.fileExists(atPath: url.path),
                  let values = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: String] else { continue }
            if try setStrings(blockIndex: s.block, values) { changed.append(s.file) }
        }
        return changed
    }
}
