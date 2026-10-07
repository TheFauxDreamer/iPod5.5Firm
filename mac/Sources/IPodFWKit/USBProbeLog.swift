import Foundation

/// The log that the usb-host-probe patch writes to iPod_Control/iTunes/iPodFirmUSBLog: each call of a
/// USB class driver (validate, initialize device, initialize interface) after the probe started the
/// host stack. Format (little-endian): "UL01", u32 count, then 64-byte records: u8 0xA5, u8 tag
/// (driver × 4 + entry), u16 0, u32 r0–r3, 20 bytes at r1, 20 bytes at r2, 4 bytes 0.
/// Tag 30 (7 × 4 + 2) is a root port record: r0 port, r1 wPortStatus | wPortChange << 16, r2 PORTSC.
/// Tag 31 (7 × 4 + 3) is a register record: r0 USBCMD, r1 USBSTS, r2 PORTSC, r3 OTGSC.
/// Refer to patches/usb-host-probe/usb_host_probe.c.
public enum USBProbeLog {
    /// The size of the file that iPodFirm makes when it sets the trigger. The patch can only write to an existing file.
    public static let fileSize = 8192
    static let drivers = [0: "Hub", 1: "Composite device", 3: "Storage", 4: "ICA camera (Canon)", 5: "PTP camera"]
    static let queueTag = 7 * 4 + 1, endpointTag = 6 * 4 + 1, transferTag = 6 * 4 + 2, irqTag = 6 * 4 + 3, completionTag = 6 * 4
    static let entries = [1: "validate", 2: "initialize device", 3: "initialize interface"]

    public struct Entry: Hashable {
        public var driver: String
        public var call: String
        public var device: String?
        public var interface: String?
        public var registers: [UInt32]

        public var text: String {
            var s = "\(driver): \(call)"
            if let interface { s += " — \(interface)" }
            if let device { s += " — \(device)" }
            return s
        }
    }

    /// All entries as numbered lines, for the pasteboard.
    public static func text(_ entries: [Entry]) -> String {
        entries.enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n")
    }

    /// nil if the data is not a log (no "UL01").
    public static func parse(_ data: [UInt8]) -> [Entry]? {
        guard data.count >= 8, Array(data[0..<4]) == Array("UL01".utf8) else { return nil }
        let count = Int(le32(data, 4))
        var out: [Entry] = []
        for i in 0..<count {
            let o = 8 + 64 * i
            guard o + 64 <= data.count, data[o] == 0xA5 else { break }
            let tag = Int(data[o + 1])
            let regs = (0..<4).map { le32(data, o + 4 + 4 * $0) }
            let atR1 = Array(data[o + 20..<o + 40]), atR2 = Array(data[o + 40..<o + 60])
            if tag == queueTag {
                out.append(Entry(driver: "Queue", call: queueText(regs, atR1, atR2), device: nil, interface: nil, registers: regs))
                continue
            }
            if tag == completionTag {
                let status = Int32(bitPattern: regs[1])
                let field = Int(atR1[10]) | Int(atR1[11]) << 8
                out.append(Entry(driver: "UIM", call: String(format: "completion — request 0x%08X, field +10 = %d, status %@, %d bytes, flags 0x%08X",
                                                              regs[0], field, status == 0 ? "correct" : String(format: "error %d (0x%08X)", status, regs[1]),
                                                              Int32(bitPattern: regs[2]), le32(atR2, 0x0C)),
                                 device: nil, interface: nil, registers: regs))
                continue
            }
            if tag == irqTag {
                out.append(Entry(driver: "UIM", call: String(format: "USB interrupt: disable %d, remove device handler %d, install host handler %d, enable %d",
                                                              Int32(bitPattern: regs[0]), Int32(bitPattern: regs[1]), Int32(bitPattern: regs[2]), Int32(bitPattern: regs[3])),
                                 device: nil, interface: nil, registers: regs))
                continue
            }
            if tag == endpointTag {
                out.append(Entry(driver: "UIM", call: String(format: "create control endpoint — address %d, endpoint %d, max packet %d, speed %d",
                                                              regs[0], regs[1], regs[2], regs[3]), device: nil, interface: nil, registers: regs))
                continue
            }
            if tag == transferTag {
                out.append(Entry(driver: "UIM", call: "control transfer — address \(regs[3]), " + stageText(regs[2], atR2),
                                 device: nil, interface: nil, registers: regs))
                continue
            }
            if tag == registerTag {
                out.append(Entry(driver: "Controller", call: registerText(regs), device: nil, interface: nil, registers: regs))
                continue
            }
            if tag == portTag {
                out.append(Entry(driver: "Root port \(regs[0])", call: portText(regs[1], regs[2]), device: nil, interface: nil, registers: regs))
                continue
            }
            var e = Entry(driver: drivers[tag >> 2] ?? "Driver \(tag >> 2)", call: entries[tag & 3] ?? "entry \(tag & 3)",
                          device: nil, interface: nil, registers: regs)
            if tag & 3 == 3 {
                e.interface = interfaceText(atR1)
                e.device = deviceText(atR2)
            } else {
                e.device = deviceText(atR1)
            }
            out.append(e)
        }
        return out
    }

    /// A USB device descriptor (18 bytes, type 1): vendor:product and class.
    static func deviceText(_ d: [UInt8]) -> String? {
        guard d.count >= 18, d[0] == 18, d[1] == 1 else { return nil }
        let vid = UInt16(d[8]) | UInt16(d[9]) << 8, pid = UInt16(d[10]) | UInt16(d[11]) << 8
        return String(format: "device %04X:%04X, class %@", vid, pid, classText(d[4], d[5], d[6]))
    }

    /// A USB interface descriptor (9 bytes, type 4): number and class.
    static func interfaceText(_ d: [UInt8]) -> String? {
        guard d.count >= 9, d[0] == 9, d[1] == 4 else { return nil }
        return "interface \(d[2]) (alternate \(d[3])), class \(classText(d[5], d[6], d[7]))"
    }

    static func classText(_ c: UInt8, _ s: UInt8, _ p: UInt8) -> String {
        let names: [UInt8: String] = [0x00: "per interface", 0x01: "audio", 0x03: "HID", 0x06: "still image",
                                      0x08: "storage", 0x09: "hub", 0x0E: "video", 0xEF: "miscellaneous", 0xFF: "vendor"]
        return String(format: "%02X/%02X/%02X", c, s, p) + (names[c].map { " (\($0))" } ?? "")
    }

    static let portTag = 7 * 4 + 2
    static let registerTag = 7 * 4 + 3

    /// The ARC (EHCI) registers USBCMD, USBSTS, PORTSC and OTGSC.
    static func registerText(_ r: [UInt32]) -> String {
        func bits(_ v: UInt32, _ names: [(UInt32, String)]) -> String {
            let set = names.filter { v & $0.0 != 0 }.map(\.1)
            return set.isEmpty ? "none" : set.joined(separator: ", ")
        }
        let speed = ["full speed", "low speed", "high speed", "speed 3"][Int(r[2] >> 26 & 3)]
        return String(format: "USBCMD 0x%08X (%@), USBSTS 0x%08X (%@), PORTSC 0x%08X (%@, %@), OTGSC 0x%08X (%@)",
                      r[0], bits(r[0], [(0x1, "run"), (0x10, "periodic on"), (0x20, "asynchronous on")]),
                      r[1], bits(r[1], [(0x1, "transfer done"), (0x2, "error"), (0x4, "port change"), (0x1000, "halted"),
                                        (0x4000, "periodic running"), (0x8000, "asynchronous running")]),
                      r[2], bits(r[2], [(0x1, "connected"), (0x2, "connect change"), (0x4, "enabled"), (0x100, "reset"),
                                        (0x1000, "power"), (0x1000000, "full speed forced")]), speed,
                      r[3], bits(r[3], [(0x100, "ID pin high"), (0x200, "VBUS valid"), (0x400, "B-session valid"),
                                        (0x800, "A-session valid"), (0x1, "VBUS discharge"), (0x2, "VBUS charge")]))
    }

    /// USB 2.0 wPortStatus and wPortChange (low and high half of `status`), and the ARC PORTSC register.
    static func portText(_ status: UInt32, _ portsc: UInt32) -> String {
        func bits(_ v: UInt32, _ names: [(UInt32, String)]) -> String {
            let set = names.filter { v & $0.0 != 0 }.map(\.1)
            return set.isEmpty ? "none" : set.joined(separator: ", ")
        }
        let ps = status & 0xFFFF, pc = status >> 16
        let speed = ["full speed", "low speed", "high speed", "speed 3"][Int(portsc >> 26 & 3)]
        let line = ["SE0", "K (low speed)", "J (full speed)", "line 3"][Int(portsc >> 10 & 3)]
        return String(format: "status 0x%04X (%@), change 0x%04X (%@), PORTSC 0x%08X (%@, %@, line %@)",
                      ps, bits(ps, [(0x1, "connected"), (0x2, "enabled"), (0x4, "suspended"), (0x8, "over-current"),
                                    (0x10, "reset"), (0x100, "power"), (0x200, "low speed"), (0x400, "high speed")]),
                      pc, bits(pc, [(0x1, "connection"), (0x2, "enable"), (0x4, "suspend"), (0x8, "over-current"), (0x10, "reset")]),
                      portsc, bits(portsc, [(0x1, "connected"), (0x4, "enabled"), (0x100, "reset"), (0x1000, "power"),
                                            (0x1000000, "full speed forced")]), speed, line)
    }

    /// One stage of a control transfer. The UIM gets three calls: setup (r2 = the 8-byte setup
    /// packet), data (r2 = the buffer) and status (r2 = 0).
    static func stageText(_ r2: UInt32, _ b: [UInt8]) -> String {
        if r2 == 0 { return "status stage" }
        if let s = setupText(b) { return "setup: " + s }
        return "data stage, buffer " + hex(b, 12)
    }

    /// A standard USB setup packet, or nil if the bytes are not one.
    static func setupText(_ b: [UInt8]) -> String? {
        guard b.count >= 8, b.prefix(8).contains(where: { $0 != 0 }) else { return nil }   // zeros: a data buffer
        let type = b[0], req = b[1], value = UInt16(b[2]) | UInt16(b[3]) << 8, length = UInt16(b[6]) | UInt16(b[7]) << 8
        guard [0x00, 0x80, 0x01, 0x81, 0x02, 0x82, 0x20, 0x21, 0x22, 0x23, 0xA0, 0xA1, 0xA2, 0xA3].contains(type) else { return nil }
        let descriptors: [UInt8: String] = [1: "device", 2: "configuration", 3: "string", 6: "device qualifier", 0x29: "hub"]
        switch req {
        case 0x06: return "GET_DESCRIPTOR \(descriptors[b[3]] ?? "type \(b[3])") \(b[2]), \(length) bytes"
        case 0x05: return "SET_ADDRESS \(value)"
        case 0x09: return "SET_CONFIGURATION \(value)"
        case 0x0B: return "SET_INTERFACE \(value)"
        case 0x00: return "GET_STATUS, \(length) bytes"
        case 0x01: return "CLEAR_FEATURE \(value)"
        case 0x03: return "SET_FEATURE \(value)"
        default: return nil
        }
    }

    static func hex(_ b: [UInt8], _ n: Int) -> String { b.prefix(n).map { String(format: "%02X", $0) }.joined() }

    /// USBINTR, the first queue head (QH) of the asynchronous list and its qTD overlay token (QH + 0x18).
    static func queueText(_ r: [UInt32], _ qh: [UInt8], _ overlay: [UInt8]) -> String {
        let token = le32(overlay, 8)                       // QH + 0x18
        let status = [(0x80, "active"), (0x40, "halted"), (0x20, "buffer error"), (0x10, "babble"),
                      (0x08, "transaction error"), (0x04, "missed micro-frame"), (0x02, "split state"), (0x01, "ping")]
            .filter { token & UInt32($0.0) != 0 }.map(\.1)
        return String(format: "USBINTR 0x%08X, ASYNCLISTADDR 0x%08X, FRINDEX 0x%X, QH %@, overlay %@, token 0x%08X (%@, %d bytes left, error count %d, PID %d)",
                      r[0], r[1], r[3], hex(qh, 16), hex(overlay, 20), token,
                      status.isEmpty ? "none" : status.joined(separator: ", "), Int(token >> 16 & 0x7FFF), Int(token >> 10 & 3), Int(token >> 8 & 3))
    }

    static func le32(_ d: [UInt8], _ o: Int) -> UInt32 {
        UInt32(d[o]) | UInt32(d[o + 1]) << 8 | UInt32(d[o + 2]) << 16 | UInt32(d[o + 3]) << 24
    }
}
