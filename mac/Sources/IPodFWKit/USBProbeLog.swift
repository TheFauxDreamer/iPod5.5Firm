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
    static let musicStartTag = 13 * 4, musicStatsTag = 13 * 4 + 1, musicChainTag = 13 * 4 + 2, musicSleepTag = 13 * 4 + 3, musicStopTag = 14 * 4, idleTag = 14 * 4 + 1
    static let artStepTag = 14 * 4 + 2, artSummaryTag = 14 * 4 + 3, artStateTag = 15 * 4, outputMadeTag = 15 * 4 + 1
    static let artCacheTag = 15 * 4 + 2, artGatesTag = 15 * 4 + 3, artQueuesTag = 16 * 4, artDBTag = 16 * 4 + 1, artLookupTag = 16 * 4 + 2, artAddTag = 16 * 4 + 3
    static let volumeRangeTag = 17 * 4, volumeSetTag = 17 * 4 + 1, hidDescTag = 17 * 4 + 2, hidReportTag = 17 * 4 + 3
    static let keyPostTag = 18 * 4, keyActionTag = 18 * 4 + 1, deviceTag = 18 * 4 + 2, playerTag = 18 * 4 + 3
    static let vbusTag = 19 * 4

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
            if tag == vbusTag {
                out.append(Entry(driver: "VBUS test", call: vbusText(regs), device: nil, interface: nil, registers: regs))
                continue
            }
            if tag == hidDescTag {
                out.append(Entry(driver: "Audio", call: hidDescriptorText(regs, atR1 + atR2), device: nil, interface: nil, registers: regs))
                continue
            }
            if tag >= audioDeviceTag && tag <= playerTag {
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
        case musicStartTag where r[3] == 1:
            return String(format: "music route on — %d Hz, output flags +0x58 %d, +0x59 %d, +0x5a %d (1 = USB), stream %d",
                          r[0], r[1] & 0xFF, r[1] >> 8 & 0xFF, r[1] >> 16 & 0xFF, r[2])
        case musicStartTag:
            return String(format: "music start — audio object 0x%08X, USB source 0x%08X, audio output 0x%08X, event 0x%08X", r[0], r[1], r[2], r[3])
        case musicStatsTag:
            return String(format: "music — %d packets sent (%d s), %d underruns, %d packets with sound, route +0x5a %d, stream %d, source +0 %d, +1 %d (1 = test signal)",
                          r[0], r[0] / 1000, r[1], r[2], r[3] & 0xFF, r[3] >> 8 & 0xFF, r[3] >> 16 & 0xFF, r[3] >> 24)
        case musicChainTag:
            return String(format: "decoder chain — codec buffers %d, USB buffers %d, queue write %d read %d, ready flag 0x1081dff6 = %d, flag 0x1081dff4 = %d, music rate %d Hz, output rate %d Hz",
                          r[0], r[1], r[2] & 0xFF, r[2] >> 8 & 0xFF, r[2] >> 16 & 0xFF, r[2] >> 24, r[3] & 0xFFFF, r[3] >> 16)
        case musicSleepTag:
            let elapsed = max(r[3], 1)
            return String(format: "CPU — %d sleeps; probe copy %d ms (%.1f %%), Apple packet fill %d ms (%.1f %%) of %d ms",
                          r[0], r[1], Double(r[1]) * 100 / Double(elapsed), r[2], Double(r[2]) * 100 / Double(elapsed), r[3])
        case idleTag:
            let phases = [1: "before the host start", 2: "host mode", 3: "tone test", 4: "music start", 5: "music"]
            return String(format: "CPU idle — %@: %.1f %% (core 1 %.1f %%) in %d ms",
                          phases[Int(r[3])] ?? "phase \(r[3])", Double(r[1]) / 10, Double(r[2]) / 10, r[0])
        case artStepTag:
            return String(format: "art step %d %@ — result 0x%X, %d µs, at %d ms", r[0], artStepName(r[0]), r[1], r[2], r[3])
        case artSummaryTag:
            return String(format: "art summary step %d %@ — %d calls, %d with result 0, longest %d µs", r[0], artStepName(r[0]), r[1], r[2], r[3])
        case artStateTag:
            return r[0] == 0
                ? String(format: "art task — no step in progress; last step %d %@, %d ms ago", r[2], artStepName(r[2]), r[3])
                : String(format: "art task — in step %d %@ for %d ms; last step %d, %d ms ago", r[0], artStepName(r[0]), r[1], r[2], r[3])
        case outputMadeTag:
            return String(format: "audio output object made again — 0x%08X → 0x%08X, flags +0x58/+0x59/+0x5a 0x%06X → 0x%06X", r[0], r[1], r[2], r[3])
        case artCacheTag:
            return String(format: "art cache (%@) — object 0x%08X, capacity +0x74 %d, +0x78 %d, +0x70 %d, +0x71 %d, +0x72 %d",
                          artPhaseName(r[3] & 0xFF), r[0], r[1], r[2], r[3] >> 8 & 0xFF, r[3] >> 16 & 0xFF, r[3] >> 24)
        case artGatesTag:
            let library = String(format: "library open +0x54 %d, +0x55 %d, requests %d, count +0xc %d",
                                 r[0] & 0xFF, r[0] >> 8 & 0xFF, r[0] >> 16 & 0xFF, r[0] >> 24)
            let photo = r[2] == 0xFFFF_FFFF
                ? "no photo import service"
                : String(format: "photo import 0x%08X state %d, active %d, the start object %@",
                         r[1], r[2] & 0xFF, r[2] >> 8 & 0xFF, r[2] >> 16 & 1 == 1 ? "yes" : "no")
            let queue = r[3] == 0xFFFF_FFFF ? "no play queue object" : String(format: "play queue +4 0x%08X", r[3])
            return "art gates — \(library); \(photo); \(queue)"
        case artQueuesTag:
            let enabled = r[0] >> 24 == 0xFF ? "no entry for the art cache" : "the art cache entry +8 = \(r[0] >> 24)"
            return String(format: "art queues (%@) — library queue %d, cache queue %d, %d cache entries, %@, library +0x30 %d, task event 0x%08X",
                          artPhaseName(r[3]), r[0] & 0xFF, r[0] >> 8 & 0xFF, r[0] >> 16 & 0xFF, enabled, r[1], r[2])
        case artDBTag:
            let handle = r[0] == 0xFFFF_FFFF ? "no database object" : String(format: "ArtworkDB handle +0xd2c 0x%08X, +0xd14 0x%08X", r[0], r[1])
            let app = r[2] == 0xFFFF_FFFF ? "no app object" : String(format: "app reload flag +0x484 %d, +0x489 %d, reload done +0x48a %d, +0x487 %d",
                                                                  r[2] & 0xFF, r[2] >> 8 & 0xFF, r[2] >> 16 & 0xFF, r[2] >> 24)
            return String(format: "art database (%@) — %@; %@; USB device state %d", artPhaseName(r[3] & 0xFF), handle, app, r[3] >> 8 & 0xFF)
        case artLookupTag where r[0] == 0xFFFF_FFFF:
            return "ArtworkDB — no ArtworkDB object"
        case artLookupTag:
            let index = r[3] & 4 == 0 ? "index lookup not run" : (r[3] & 2 != 0 ? "index lookup correct" : "index lookup failed")
            return String(format: "ArtworkDB — first word 0x%08X (%@), %d entries, +6 %d, index 0x%08X; list lookup %@, %@ (dbid …%06X)",
                          r[0], r[0] == 0x6974_696C ? "correct" : "wrong", r[1] & 0xFF_FFFF, r[1] >> 24, r[2],
                          r[3] & 1 != 0 ? "correct" : "failed", index, r[3] >> 8)
        case artAddTag where r[1] == 0xFFFF_FFFF:
            return String(format: "art add test %d (%@) — not run: no art cache or no ArtworkDB entry", r[3] >> 8, artPhaseName(r[3] & 0xFF))
        case artAddTag:
            let added = (r[2] & 0xFFFF) > (r[1] & 0xFFFF) ? "added" : "nothing added"
            return String(format: "art add test %d (%@) — dbid …%08X: +0x78 %d → %d, +0xc %d → %d, %@",
                          r[3] >> 8, artPhaseName(r[3] & 0xFF), r[0], r[1] & 0xFFFF, r[2] & 0xFFFF, r[1] >> 16, r[2] >> 16, added)
        case volumeRangeTag where r[3] & 0xFF < 8 || r[3] & 0xFF == 0xFF:
            return "volume range — no answer; the probe uses −60 dB to 0 dB"
        case volumeRangeTag:
            return String(format: "volume range — %@ to %@, resolution %.4f dB, %d sub-ranges", decibels(r[0]), decibels(r[1]), Double(r[2]) / 256, r[3] >> 8)
        case volumeSetTag:
            return String(format: "volume — iPod output %d of 256 → %@; status channel 1 0x%02X, channel 2 0x%02X; request %d, %d errors",
                          r[0], decibels(r[1]), r[2] & 0xFF, r[2] >> 8 & 0xFF, r[3] & 0xFFFF, r[3] >> 16)
        case hidReportTag:
            let length = Int(r[0] >> 8 & 0xFF)
            let bytes = (1...3).flatMap { i in (0..<4).map { UInt8(r[i] >> (8 * $0) & 0xFF) } }.prefix(min(length, 12))
            return String(format: "button report — interface %d, %d bytes: %@; pushed: %@; %d errors",
                          r[0] & 0xFF, length, hex(Array(bytes), 12), buttonNames(r[0] >> 16 & 0xFF), r[0] >> 24)
        case keyPostTag where r[1] == 0 && r[2] == 0 && r[3] == 0:
            return String(format: "key to the UI task (0x1ac198) — %@ %@", keyName(r[0] & 0xFF), keyType(r[0] >> 8 & 0xFF))
        case keyPostTag:
            return String(format: "key posted — %@ %@, result %d, sender 0x%08X, app port 0x%08X",
                          keyName(r[0] & 0xFF), keyType(r[0] >> 8 & 0xFF), Int32(bitPattern: r[1]), r[2], r[3])
        case keyActionTag:
            return String(format: "key in the UI task — %@ %@, volume level %d → %d", keyName(r[0] & 0xFF), keyType(r[0] >> 8 & 0xFF), r[1], r[2])
        case deviceTag:
            let otg = String(format: "OTGSC 0x%08X (VBUS %@)", r[3], r[3] & 0x800 != 0 ? "present" : "absent")
            switch r[0] {
            case 1: return "device task — the start of the device mode is blocked (host mode runs); " + otg
            case 2: return "device task — the start of the device mode is allowed; " + otg
            case 3: return "device task — Apple's stop of the device session ran; " + otg
            case 4: return "device task — the stop is skipped (host mode runs, no controller reset); " + otg
            case 5: return String(format: "device task — before the host start: %@ (%d ms); %@",
                                  r[1] != 0 ? "the device session stopped" : "no device session", r[2], otg)
            case 6:
                let error = [0x673: "a hub is not allowed", 0x67D: "too many hubs", 0x68C: "no driver"][Int(r[2])] ?? String(format: "error 0x%X", r[2])
                return String(format: "USB host message not shown (host mode runs) — type %d, %@", r[1], error)
            default: return String(format: "device task — event %d; %@", r[0], otg)
            }
        case playerTag:
            let state = [1: "playing", 2: "paused", 0xFF: "unknown"][Int(r[0])] ?? "stopped (\(r[0]))"
            let moment = [1: "before the stop", 2: "after the stop", 3: "after the pause key", 5: "later"][Int(r[1])] ?? "moment \(r[1])"
            return String(format: "player — %@: %@; codec buffers %d, USB buffers %d", moment, state, r[2], r[3])
        case musicStopTag:
            let reason = [1: "the dock was disconnected", 2: "the device does not answer"][Int(r[0])] ?? "reason \(r[0])"
            return String(format: "music stopped — %@, %d packets, %d siTD errors, %d sleeps", reason, r[1], r[2], r[3])
        default:
            return String(format: "memory — control page 0x%08X, siTDs 0x%08X, frame list 0x%08X, ASYNCLISTADDR 0x%08X", r[0], r[1], r[2], r[3])
        }
    }

    /// The key codes of the button records: the Simple Remote codes (table 0x63ef30, version 1.23), and the codes of
    /// version 1.22 (0x3a is Stop, not Play/Pause; 0x7b and 0x7d were private codes).
    static func keyName(_ code: UInt32) -> String {
        [0x1C: "play/pause", 0x20: "volume +", 0x1F: "volume −", 0x1E: "next track", 0x1D: "previous track",
         0x3A: "stop", 0x3C: "pause", 0x7B: "volume + (private)", 0x7D: "volume − (private)"][code] ?? String(format: "key 0x%02X", code)
    }

    /// Version 1.23: 1 push, 0 release. Version 1.22: the event types 4, 5 and 7.
    static func keyType(_ type: UInt32) -> String {
        [0: "release", 1: "push", 4: "push", 5: "repeat", 6: "held", 7: "release"][type] ?? "type \(type)"
    }

    /// A UAC2 volume value in 1/256 dB (16 bits, signed); 0x8000 is silence.
    static func decibels(_ value: UInt32) -> String {
        value & 0xFFFF == 0x8000 ? "silence" : String(format: "%.1f dB", Double(Int16(truncatingIfNeeded: value)) / 256)
    }

    /// The buttons of a decoded report (version 1.21): bit 0 volume +, 1 volume −, 2 play/pause, 3 next, 4 previous; 0x80 a different report.
    static func buttonNames(_ mask: UInt32) -> String {
        if mask & 0x80 != 0 { return "a report with a different ID" }
        let names = ["volume +", "volume −", "play/pause", "next", "previous"]
        let pushed = names.enumerated().filter { mask & (1 << UInt32($0.offset)) != 0 }.map(\.element)
        return pushed.isEmpty ? "none" : pushed.joined(separator: ", ")
    }

    /// The HID report descriptor record (version 1.21): r0 interface | endpoint << 8 | bytes << 16, r1 offset,
    /// r2 the bits of volume +, volume −, play/pause and the report ID, r3 the bits of next and previous and the array; 40 bytes.
    static func hidDescriptorText(_ r: [UInt32], _ bytes: [UInt8]) -> String {
        let total = Int(r[0] >> 16 & 0xFF), offset = Int(r[1])
        if total == 0xFF { return String(format: "HID report descriptor — interface %d: no answer", r[0] & 0xFF) }
        func bit(_ b: UInt32) -> String { b == 0xFF ? "none" : b == 0xFE ? "after bit 253" : "bit \(b)" }
        let chunk = Array(bytes.prefix(max(0, min(40, total - offset))))
        var text = String(format: "HID report descriptor — interface %d, endpoint %d IN, %d bytes; bytes %d–%d: %@",
                          r[0] & 0xFF, r[0] >> 8 & 0xFF, total, offset, offset + max(chunk.count, 1) - 1, hex(chunk, 40))
        if offset == 0 {
            let array = r[3] >> 16 == 0 ? "no array" : String(format: "an array of %d fields of %d bits", r[3] >> 24, r[3] >> 16 & 0xFF)
            text += String(format: "; volume + %@, volume − %@, play/pause %@, next %@, previous %@, report ID %d, %@",
                           bit(r[2] & 0xFF), bit(r[2] >> 8 & 0xFF), bit(r[2] >> 16 & 0xFF), bit(r[3] & 0xFF), bit(r[3] >> 8 & 0xFF), r[2] >> 24, array)
        }
        return text
    }

    /// The phase of an art record (version 1.14): the same values as the idle records.
    static func artPhaseName(_ phase: UInt32) -> String {
        [0: "before the host start", 1: "after the host start", 2: "host mode", 4: "after the audio test", 5: "later"][phase] ?? "phase \(phase)"
    }

    /// The steps of the trace of ArtworkLoadTask (0x205db4).
    static func artStepName(_ step: UInt32) -> String {
        let names: [UInt32: String] = [1: "(wait for a request)", 2: "(gate query 1)", 3: "(gate query 2)", 4: "(gate request)",
                                       5: "(lock 1)", 6: "(lock 2)", 7: "(request lookup 1)", 8: "(request lookup 2)",
                                       9: "(artwork lookup)", 10: "(handle 1)", 11: "(handle 2)", 12: "(image load)",
                                       13: "(image decode)", 14: "(gate release)"]
        return names[step] ?? ""
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
                      r[3], otgscText(r[3]))
    }

    /// The ARC OTGSC register: the VBUS comparators (bit 9 above approximately 4.4 V, bits 10 and 11 above
    /// approximately 0.8–4.0 V, bit 12 below approximately 0.8 V) and the VBUS controls.
    static func otgscText(_ v: UInt32) -> String {
        let names: [(UInt32, String)] = [(0x100, "ID pin high"), (0x200, "VBUS valid"), (0x400, "A-session valid"),
                                         (0x800, "B-session valid"), (0x1000, "B-session end"), (0x1, "VBUS discharge"), (0x2, "VBUS charge")]
        let set = names.filter { v & $0.0 != 0 }.map(\.1)
        return set.isEmpty ? "none" : set.joined(separator: ", ")
    }

    /// The VBUS test (version 1.29): r0 step | second << 8, r1 OTGSC, r2 PORTSC, r3 GPIOL. Step 0xFF: r1 PMU type, r2 hardware ID.
/// The VBUS level comes from bit 12 (B-session end) first: in host mode bits 9–11 stay on.
    static func vbusText(_ r: [UInt32]) -> String {
        let step = r[0] & 0xFF, second = r[0] >> 8 & 0xFF
        if step == 0xFF {
            let pmu = [2: "PMU type 2 (ID 0x24)", 3: "PCF50605 (D2REGC1 = register 0x25)"][Int(r[1])] ?? "PMU type \(r[1])"
            return String(format: "start — %@, hardware ID 0x%08X", pmu, r[2])
        }
        let names = [1: "Apple's host mode state", 2: "accessory power (pin 18) off", 3: "port power (PP) inverted",
                     4: "VBUS charge on", 5: "all on, connect the EarPods"]
        // In host mode the controller holds bits 9–11 on (real iPod, 2026-10-17: "VBUS valid" and "B-session end" at the
        // same time). Only bit 12 (B-session end) measures VBUS there.
        let level = r[1] & 0x1000 != 0 ? "below approximately 0.8 V" : r[1] & 0xE00 == 0xE00 ? "above approximately 0.8 V" : "above approximately 0.8 V, below 4.4 V"
        return String(format: "step %d (%@), %d s — VBUS %@; OTGSC 0x%08X (%@), PORTSC 0x%08X (power %@), USB power pin %@",
                      step, names[Int(step)] ?? "step \(step)", second, level, r[1], otgscText(r[1]), r[2],
                      r[2] & 0x1000 != 0 ? "on" : "off", r[3] & 0x10 != 0 ? "high" : "low")
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
