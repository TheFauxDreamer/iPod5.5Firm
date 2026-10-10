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
    public static let fileSize = 32768
    static let drivers = [0: "Hub", 1: "Composite device", 3: "Storage", 4: "ICA camera (Canon)", 5: "PTP camera"]
    static let asyncQHTag = 9 * 4 + 1, periodicQHTag = 9 * 4 + 2, periodicSoftTag = 9 * 4 + 3, experimentTag = 10 * 4
    static let addDeviceTag = 7 * 4, interruptEndpointTag = 8 * 4 + 1, interruptTransferTag = 8 * 4 + 2, interruptCompletionTag = 8 * 4 + 3
    static let queueTag = 7 * 4 + 1, endpointTag = 6 * 4 + 1, transferTag = 6 * 4 + 2, irqTag = 6 * 4 + 3, completionTag = 6 * 4
    static let entries = [1: "validate", 2: "initialize device", 3: "initialize interface"]
    static let dataTag = 11 * 4
    static let audioDeviceTag = 12 * 4, audioRequestTag = 12 * 4 + 1, audioStreamTag = 12 * 4 + 2, audioMemoryTag = 12 * 4 + 3

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
        var received: [UInt8] = [], dataKey: (UInt32, UInt32)?
        for i in 0..<count {
            let o = 8 + 64 * i
            guard o + 64 <= data.count, data[o] == 0xA5 else { break }
            let tag = Int(data[o + 1])
            let regs = (0..<4).map { le32(data, o + 4 + 4 * $0) }
            let atR1 = Array(data[o + 20..<o + 40]), atR2 = Array(data[o + 40..<o + 60])
            if tag >= audioDeviceTag && tag <= audioMemoryTag {
                out.append(Entry(driver: "Audio", call: audioText(tag, regs), device: nil, interface: nil, registers: regs))
                continue
            }
            if tag == dataTag {
                // Records of 40 bytes of one GET_DESCRIPTOR configuration answer: r0 request, r1 buffer, r2 offset, r3 length.
                let length = Int(regs[3]), offset = Int(regs[2])
                if offset == 0 || dataKey.map({ $0 != (regs[0], regs[1]) }) ?? true { received = [] }
                dataKey = (regs[0], regs[1])
                let chunk = Array((atR1 + atR2).prefix(max(0, min(40, length - offset))))
                if received.count == offset { received += chunk }
                out.append(Entry(driver: "Data", call: String(format: "configuration descriptor, bytes %d–%d of %d: %@",
                                                               offset, offset + chunk.count - 1, length, hex(chunk, 40)),
                                 device: nil, interface: nil, registers: regs))
                if offset + 40 >= length, received.count == length {
                    for line in configurationText(received) {
                        out.append(Entry(driver: "Configuration", call: line, device: nil, interface: nil, registers: regs))
                    }
                }
                continue
            }
            if tag == queueTag {
                out.append(Entry(driver: "Queue", call: queueText(regs, atR1, atR2), device: nil, interface: nil, registers: regs))
                continue
            }
            if tag == periodicSoftTag {
                out.append(Entry(driver: "Periodic table", call: String(format: "frame %d: frame list 0x%08X, queue head 0x%08X (link 0x%08X), words %@, +0x30 %@",
                                                                         regs[0], regs[1], regs[2], regs[3], hex(atR1, 20), hex(atR2, 16)),
                                 device: nil, interface: nil, registers: regs))
                continue
            }
            if tag == experimentTag {
                out.append(Entry(driver: "Experiment", call: String(format: "periodic schedule off for 2 s: USBCMD 0x%08X -> 0x%08X, USBSTS 0x%08X (the queue heads follow)",
                                                                     regs[0], regs[1], regs[2]),
                                 device: nil, interface: nil, registers: regs))
                continue
            }
            if tag == asyncQHTag || tag == periodicQHTag {
                out.append(Entry(driver: tag == asyncQHTag ? "Async QH" : "Periodic QH", call: qhText(regs), device: nil, interface: nil, registers: regs))
                continue
            }
            if tag == interruptCompletionTag {
                let status = Int32(bitPattern: regs[1])
                out.append(Entry(driver: "UIM", call: String(format: "interrupt completion — request 0x%08X, status %@, %d bytes, request bytes %@",
                                                              regs[0], status == 0 ? "correct" : String(format: "error %d (0x%08X)", status, regs[1]),
                                                              Int32(bitPattern: regs[2]), hex(atR1, 20)),
                                 device: nil, interface: nil, registers: regs))
                continue
            }
            if tag == interruptEndpointTag {
                out.append(Entry(driver: "UIM", call: String(format: "create interrupt endpoint — address %d, endpoint %d, r2 %d, r3 %d",
                                                              regs[0], regs[1], regs[2], regs[3]), device: nil, interface: nil, registers: regs))
                continue
            }
            if tag == interruptTransferTag {
                out.append(Entry(driver: "UIM", call: String(format: "interrupt transfer — address %d, endpoint %d, r2 0x%X, r3 0x%X",
                                                              regs[0], regs[1], regs[2], regs[3]), device: nil, interface: nil, registers: regs))
                continue
            }
            if tag == addDeviceTag {
                out.append(Entry(driver: "Expert", call: "add device (driver selection), port \(regs[2])", device: deviceText(atR1), interface: nil, registers: regs))
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

    /// The isochronous test (Stage 2): the audio device, a control request, the stream result, the memory.
    static func audioText(_ tag: Int, _ r: [UInt32]) -> String {
        switch tag {
        case audioDeviceTag:
            return String(format: "device found — address %d, interface %d alternate %d, endpoint %d OUT, max packet %d, clock source %d",
                          r[0], r[1] & 0xFF, r[1] >> 8 & 0xFF, r[1] >> 16 & 0xFF, r[2], r[3])
        case audioRequestTag:
            let setup = (0..<4).map { UInt8(r[0] >> (8 * $0) & 0xFF) } + (0..<4).map { UInt8(r[1] >> (8 * $0) & 0xFF) }
            let name: String
            if setup[0] == 0x01 && setup[1] == 0x0B { name = "SET_INTERFACE \(setup[4]) alternate \(setup[2])" }
            else if setup[0] == 0x21 && setup[1] == 0x01 { name = "SET_CUR sampling frequency, clock \(setup[5])" }
            else { name = "request " + hex(setup, 8) }
            let status = r[3] & 0xFF, active = status & 0x80 != 0
            let result = active ? "no answer (still active)" : status == 0 ? "correct" : (status & 0x40 != 0 ? "stall or error" : "error") + String(format: " (0x%02X)", status)
            return String(format: "%@: %@, setup token 0x%08X, status token 0x%08X", name, result, r[2], r[3])
        case audioStreamTag:
            return String(format: "1 kHz tone: %d frames sent, %d frames with an error, last error 0x%08X, frames %d to %d",
                          r[0], r[1], r[2], r[3] & 0xFFFF, r[3] >> 16)
        default:
            return String(format: "memory — control page 0x%08X, siTDs 0x%08X, frame list 0x%08X, ASYNCLISTADDR 0x%08X", r[0], r[1], r[2], r[3])
        }
    }

    /// The descriptors in a configuration descriptor, one line each. The answer can be shorter than
    /// wTotalLength (the first request reads only 4 or 9 bytes).
    static func configurationText(_ d: [UInt8]) -> [String] {
        var lines: [String] = [], o = 0
        while o + 2 <= d.count {
            let len = Int(d[o]), type = d[o + 1]
            guard len >= 2 else { break }
            let b = Array(d[o..<min(d.count, o + len)])
            func u16(_ i: Int) -> Int { i + 1 < b.count ? Int(b[i]) | Int(b[i + 1]) << 8 : 0 }
            func u24(_ i: Int) -> Int { i + 2 < b.count ? Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 : 0 }
            var t: String
            switch type {
            case 2 where b.count >= 9:
                t = "configuration \(b[5]): total length \(u16(2)), \(b[4]) interfaces, attributes 0x\(String(format: "%02X", b[7])), power \(Int(b[8]) * 2) mA"
            case 4 where b.count >= 9:
                t = "interface \(b[2]) alternate \(b[3]): \(b[4]) endpoints, class \(classText(b[5], b[6], b[7]))"
                if b[5] == 1 { t += [1: " (control)", 2: " (streaming)", 3: " (MIDI)"][b[6]] ?? "" }
                t += b[7] == 0x20 ? ", USB Audio Class 2" : (b[5] == 1 ? ", USB Audio Class 1" : "")
            case 5 where b.count >= 7:
                let attr = b[3], kinds = ["control", "isochronous", "bulk", "interrupt"], sync = ["", ", no sync", ", asynchronous", ", adaptive", ", synchronous"]
                t = String(format: "endpoint 0x%02X (%@ %@%@), max packet %d, interval %d", b[2], b[2] & 0x80 != 0 ? "IN" : "OUT",
                           kinds[Int(attr & 3)], attr & 3 == 1 ? sync[Int(attr >> 2 & 3) + 1] : "", u16(4), b[6])
            case 11 where b.count >= 8:
                t = "interface association: first interface \(b[2]), \(b[3]) interfaces, class \(classText(b[4], b[5], b[6]))"
            case 0x24 where b.count >= 3:
                t = "audio class interface descriptor, subtype \(b[2])"
                if b[2] == 2, b.count >= 8, b[7] > 0, b.count >= 8 + 3 * Int(b[7]) {   // UAC1 FORMAT_TYPE I
                    let rates = (0..<Int(b[7])).map { u24(8 + 3 * $0) }
                    t += ": format type \(b[3]), \(b[4]) channels, \(b[5]) bytes per sample, \(b[6]) bits, rates \(rates.map(String.init).joined(separator: ", ")) Hz"
                }
            case 0x25 where b.count >= 3:
                t = "audio class endpoint descriptor, subtype \(b[2])"
            default:
                t = "descriptor type 0x\(String(format: "%02X", type))"
            }
            lines.append(t + " — " + hex(b, 64))
            o += len
        }
        return lines
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

    /// An EHCI queue head: r0 address, r1 endpoint characteristics, r2 capabilities, r3 overlay token.
    static func qhText(_ r: [UInt32]) -> String {
        let chars = r[1], caps = r[2], token = r[3]
        let speed = ["full", "low", "high", "3"][Int(chars >> 12 & 3)]
        let status = [(0x80, "active"), (0x40, "halted"), (0x20, "buffer error"), (0x10, "babble"),
                      (0x08, "transaction error"), (0x04, "missed micro-frame"), (0x02, "split state"), (0x01, "ping")]
            .filter { token & UInt32($0.0) != 0 }.map(\.1)
        return String(format: "0x%08X — address %d, endpoint %d, %@ speed, max packet %d, S-mask 0x%02X, C-mask 0x%02X, hub %d port %d, token 0x%08X (%@, %d bytes left, PID %d)",
                      r[0], Int(chars & 0x7F), Int(chars >> 8 & 0xF), speed, Int(chars >> 16 & 0x7FF),
                      Int(caps & 0xFF), Int(caps >> 8 & 0xFF), Int(caps >> 16 & 0x7F), Int(caps >> 23 & 0x7F),
                      token, status.isEmpty ? "none" : status.joined(separator: ", "), Int(token >> 16 & 0x7FFF), Int(token >> 8 & 3))
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
