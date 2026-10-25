import Foundation

// The hibernation image of the iPod, and the repair of a partition that lost it.
//
// The file iPod_Control/Device/SysInfo of the iPod is not the hibernation image.
// The hibernation image is the image "hibe" of the firmware partition. The image holds
// a snapshot of the memory of the iPod. The firmware uses the snapshot to start faster.
// The image is 64 MB on the iPod Video.
//
// The image "hibe" is the last image of the partition. The firmware reads the image
// through the directory. The firmware does not use a fixed place for the image. The app
// never writes or moves the image. The app only copies it.
//
// A partition without the image "hibe" cannot take a larger "osos". The function
// makeRoom of the partition moves the image "rsrc" to the space after the last image.
// Without the image "hibe", the space after the last image is the space after the image
// "aupd". The image "rsrc" moves there. The image "hibe" is the only image that holds
// the space.
//
// A partition without the image "hibe" also holds the data of a former build after the
// last image. The data is a copy of the image "osos" and a copy of the image "hibe". The
// data is at the place where the image "rsrc" must go. The function makeRoom refuses to
// write the image "rsrc" there.
//
// The research is in [../../re/firmware-hibe.md](../../re/firmware-hibe.md).
// This is the Swift version of src/ipodfw/hibe.py.

public enum Hibe {
    /// The name of the image in the directory of the partition. The name is
    /// byte-reversed in the directory: "ebih".
    public static let name = "hibe"

    /// The size of the image on the iPod Video: 64 MB and 2 KB.
    public static let length = 0x4000800

    /// The smallest size that `restore` accepts. The size of the image of the iPod
    /// Video is `length`. The function accepts a smaller image so that the tests can
    /// use a small image.
    public static let minimumLength = 0x1000

    /// The gap between the end of the image "aupd" and the start of the image "hibe".
    /// The research measured the place of the image "hibe" in the backups of the owner.
    /// The gap is the same in all of them.
    public static let gap = 0x1000

    /// The result of the check of the image "hibe" of a partition.
    public struct Report {
        public var present = false        // the partition has the image "hibe"
        public var length = 0              // the size of the image in the directory
        public var offset = 0              // the place of the image in the partition
        public var staleBytes = 0          // the bytes of old data after the last image
        public var staleHead = Data()      // the first bytes of the old data
        public var ok = false              // the partition is in the state that the app expects
        public var notes: [String] = []
    }

    /// Check the image "hibe" of a partition and the data after the last image.
    ///
    /// The function does not change the partition. The hibernation area is the image "hibe"
    /// when the directory has the entry. Without the entry, the area keeps its fixed place
    /// after the image "aupd", and the function finds it by the header of the snapshot.
    public static func check(_ partition: FirmwarePartition) -> Report {
        var report = Report()
        if partition.has(name) {
            let entry = try? partition.entry(name)
            if let entry {
                report.present = true
                report.length = Int(entry.length)
                report.offset = Int(entry.devOffset)
                report.ok = true
            }
            return report
        }
        report.notes.append("The partition has no entry for the image hibe.")
        if let area = partition.hibeArea() {
            report.offset = area.devOffset
            report.length = area.length
            report.notes.append(
                "The hibernation area of the iPod is intact at 0x\(String(area.devOffset, radix: 16)), "
                + "0x\(String(area.length, radix: 16)) bytes. Only the entry of the directory is missing. "
                + "A patch flashes with or without the entry: the image rsrc goes after the area. "
                + "The repair adds the entry only.")
            return report
        }
        let lastEnd = partition.entries.map { Int($0.devOffset) + Int($0.length) }.max() ?? 0
        let aligned = (lastEnd + 0x7FF) / 0x800 * 0x800
        let start = partition.imageBase + aligned
        let length = Int((try? partition.entry("rsrc"))?.length ?? 0)
        let region = partition.data[start..<min(start + length, partition.data.count)]
        report.staleBytes = region.reduce(0) { $0 + ($1 == 0 ? 0 : 1) }
        report.staleHead = Data(region.prefix(16))
        report.notes.append(
            "The space after the last image holds \(report.staleBytes) bytes of data that is not a "
            + "hibernation area. The image rsrc must go there. Clear the data with the repair, "
            + "or restore the iPod with Finder.")
        return report
    }

    /// The place of the image "hibe" in the partition.
    ///
    /// The place is the place that the image has on a healthy partition: the image
    /// follows the image "aupd" with a gap of 0x1000 bytes.
    public static func offset(in partition: FirmwarePartition) throws -> UInt32 {
        let aupd = try partition.entry("aupd")
        return aupd.devOffset + aupd.length + UInt32(gap)
    }

    /// Put the entry of the image "hibe" back into a partition of an iPod.
    ///
    /// The repair is minimal. When the hibernation area of the iPod is intact (a valid
    /// header of a snapshot is at the fixed place), the function writes the entry of the
    /// directory only. The data of the area does not change: the area holds the memory of
    /// the iPod, and the memory is newer than any backup. When no valid header is there,
    /// the function clears the space after the last image and writes the snapshot `hibe`
    /// from a backup, because the area is not usable.
    public static func restore(_ partitionData: [UInt8], hibe image: [UInt8]? = nil) throws -> [UInt8] {
        let partition = try FirmwarePartition(data: partitionData)
        if partition.has(name) {
            throw FirmwareError("The partition already has the image hibe.")
        }
        if partition.hibeArea() != nil, image == nil {
            // The hibernation area is intact. Write the entry only.
            var out = partitionData
            try addHibeEntry(into: &out)
            return out
        }
        guard let image else {
            throw FirmwareError("The hibernation area has no valid header; give a snapshot from a backup.")
        }
        guard image.count >= minimumLength else {
            throw FirmwareError("The image hibe must have at least \(minimumLength) bytes, it has \(image.count).")
        }
        let offset = try self.offset(in: partition)
        let start = partition.imageBase + Int(offset)
        guard start + image.count <= partitionData.count else {
            throw FirmwareError("The image hibe does not fit in the partition.")
        }
        // No image may cover the hibernation area.
        for e in partition.entries {
            let a = partition.imageBase + Int(e.devOffset)
            if a < start + image.count && a + Int(e.length) > start {
                throw FirmwareError("The image \(e.name) covers the hibernation area; the repair is not safe.")
            }
        }
        var out = partitionData
        let lastEnd = partition.entries.map { Int($0.devOffset) + Int($0.length) }.max() ?? 0
        let aligned = (lastEnd + 0x7FF) / 0x800 * 0x800
        let staleStart = partition.imageBase + aligned
        let staleEnd = start + image.count
        guard staleEnd <= out.count else {
            throw FirmwareError("The space after the last image is outside the partition.")
        }
        out.replaceSubrange(staleStart..<staleEnd, with: [UInt8](repeating: 0, count: staleEnd - staleStart))
        out.replaceSubrange(start..<(start + image.count), with: image)
        try addHibeEntry(into: &out)
        return out
    }

    /// Write the entry of the image "hibe" into the directory of a partition, without its data.
    ///
    /// The fields come from the healthy partitions of the research, and the place and the
    /// size come from the hibernation area of the partition. Refer to re/firmware-hibe.md.
    static func addHibeEntry(into out: inout [UInt8]) throws {
        let partition = try FirmwarePartition(data: out)
        guard !partition.has(name) else {
            throw FirmwareError("The partition already has the image hibe.")
        }
        guard let area = partition.hibeArea() else {
            throw FirmwareError("The partition has no hibernation area for the image hibe.")
        }
        let directory = partition.dirOffset
        let tags = [Array("!ATA".utf8), Array("DNAN".utf8)]
        var added = false
        for index in 0..<10 {
            let at = directory + index * 40
            guard tags.contains(Array(out[at..<at + 4])) else {
                var entry = [UInt8](repeating: 0, count: 40)
                entry.replaceSubrange(0..<4, with: Array("!ATA".utf8))
                entry.replaceSubrange(4..<8, with: Array("ebih".utf8))
                put32(&entry, 8, 1)                        // the image id
                put32(&entry, 12, UInt32(area.devOffset))  // the place of the image
                put32(&entry, 16, UInt32(area.length))     // the size of the image
                // The load address is the address of the memory of the iPod, 0x10000000.
                // The second load address is 0xffffffff. The research measured these
                // values in the healthy partition of the owner. The entry point, the
                // checksum and the version stay 0. The image is not code.
                put32(&entry, 20, 0x10000000)
                put32(&entry, 24, 0)
                put32(&entry, 28, 0)
                put32(&entry, 32, 0)
                put32(&entry, 36, 0xFFFFFFFF)
                out.replaceSubrange(at..<(at + 40), with: entry)
                added = true
                break
            }
        }
        guard added else {
            throw FirmwareError("The directory of the partition has no free entry.")
        }
    }

    /// Find a backup that has the image "hibe". Give the path and the image.
    ///
    /// The function reads the files in the folder. The function gives nil when no file
    /// has the image.
    public static func findInBackups(_ directory: URL) -> (URL, [UInt8])? {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return nil }
        // The image hibe is a snapshot of the memory of the iPod. The iPod writes a new
        // snapshot now and then. Thus the newest backup has the newest snapshot. The
        // function uses the time of the file, not its name.
        func modified(_ name: String) -> Date {
            let path = directory.appendingPathComponent(name).path
            let attrs = try? fm.attributesOfItem(atPath: path)
            return (attrs?[.modificationDate] as? Date) ?? Date.distantPast
        }
        let files = names.filter { $0.hasSuffix(".bin") }.sorted { modified($0) > modified($1) }
        for file in files {
            let path = directory.appendingPathComponent(file)
            guard let data = try? [UInt8](Data(contentsOf: path)),
                  let partition = try? FirmwarePartition(data: data),
                  partition.has(Hibe.name),
                  (try? partition.image(Hibe.name).count) == length else { continue }
            if let image = try? partition.image(Hibe.name) {
                return (path, image)
            }
        }
        return nil
    }
}
