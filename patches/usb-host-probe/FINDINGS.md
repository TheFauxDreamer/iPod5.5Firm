# USB host probe: findings

This document gives the full picture of the USB host exploration on the iPod 5.5G. Update it after each test. The plan is in [USB-AUDIO-OUT.md](../../USB-AUDIO-OUT.md). The research notes in the sequence of the work are in [re/usb-host.md](../../re/usb-host.md). The patch is described in [docs/modifications.md](../../docs/modifications.md#usb-host-probe).

## The goal

USB-C audio out: the iPod as USB host to USB-C headphones and USB DACs. The probe is the first stage. It shows how far the Apple USB host stack gets with a device on the USB-C mod.

## Summary of the status (2026-10-08)

| Step | Status | Evidence |
|---|---|---|
| Start the USB host stack without a Camera Connector | Works | The host mode tone; log: UIM init, root hub set up |
| VBUS (5 V) from a charger through an adapter or a dock | Works | OTGSC "VBUS valid" |
| Connection and port reset | Works | Port status 0x0103 after the reset |
| High speed | Connects, then no answer was processed | Log of 2026-10-07 (third log) |
| Full speed (forced) | Works | PORTSC: PFSC set, PSPD 0 |
| Transfer completion interrupt | Works after a fix | The device driver held the USB interrupt. The probe removes its handler. |
| First requests to the device (GET_DESCRIPTOR, SET_ADDRESS, GET_DESCRIPTOR 18 bytes) | Works | The dock's hub descriptor: USB 2.1, class 09, packet size 64 |
| Driver selection for an external hub | Works with the probe | "Add device" 0xd377c refuses a second hub unless g[0] != 0. With g[0] = 2, the dock's hub (2109:2817, VIA Labs VL817) was accepted, configured and its hub descriptor read. |
| Ports of the external hub | Powered | The hub driver sent SET_FEATURE PORT_POWER five times and started the status-change interrupt transfer (0.1.68). |
| Port power of the external hub | Works after the periodic fix | The PORT_POWER stall was a result of the periodic bug (0.1.72). |
| Port changes of the external hub, devices behind it | Works after the periodic fix | 0.1.72: the dock's hub reports port changes; the hub driver resets the ports and enumerates the devices behind it. |
| A card reader through a hub | **Works** | 0.1.72: 05E3:0749 (Genesys Logic) and 2537:1081 (Norelsys) through the dock: "Storage: initialize interface" (class 08/06/50), string descriptors, GET_MAX_LUN, bulk QHs for endpoints 1 and 2. The storage tone sounded. |
| Billboard device of the dock | No driver (normal) | 291A:8346, class 0x11 |
| Photo import screen | Accepts the storage | 0.1.72: the screen did not say "unsupported device" but a text like "ready for SD card" (the owner did not remember the exact words). Probably the dock's own empty card slot (2537:1081) or a state before the card was ready. Not examined further; it is not necessary for audio. |
| Configuration of the USB-C EarPods | **Read** | 2026-10-08 (iPodFirm 0.1.79): the composite driver took the EarPods (class EF/02), read the configuration and set configuration 1. USB Audio Class 2, full speed, a synchronous isochronous OUT endpoint. Refer to "The USB-C EarPods" below. |
| An audio device (Apple USB-C EarPods) through the dock | **Enumerated; driver with the probe** | 2026-10-08: 05AC:110B, USB 2.01, device class EF/02/01 (interface association), packet size 64, address 106, full speed. "Add device" ran, but no class driver accepted the device. The configuration descriptor was not read. |
| Isochronous transfers | Not available | The UIM entries are stubs (0xd4820, 0xd4828) |

## The hardware of the tests

| Item | Details |
|---|---|
| iPod | iPod 5.5G, 64 MB RAM, 1 TB flash, USB-C mod (wired as a device) |
| Adapter | 3-in-1 USB-C adapter: USB-A socket, 3.5 mm jack (a USB sound card), PD charging socket. It contains a hub. |
| Dock | A USB-C dock with its own power supply. It contains a USB 2.1 hub. |
| Storage | A USB card reader with a 128 GB SDXC card (FAT32, photos in DCIM) |
| Audio devices for later | Apple EarPods (USB-C), Apple USB-C to 3.5 mm Headphone Jack Adapter |

### The supply voltage for USB devices

- The iPod has no 5 V source for USB. VBUS must come from outside (a dock or an adapter with a charger).
- Dock pin 18 supplies 3.3 V accessory power. The iPod Camera Connector has its own step-up converter that changes this 3.3 V to 5 V for its USB port. Thus the iPod never supplied a low USB voltage.
- The USB-C mod connects VBUS to the USB power input of the iPod, not to pin 18. The firmware has no output that it can switch to VBUS.
- USB 2.0 devices must operate down to approximately 4.4 V. The minimum voltage of the USB-C EarPods is not known. No measurement is published.
- Optional bench test (after the EarPods enumeration test): use a USB-C pass-through breakout with VBUS cut. Supply the data from a Mac and VBUS from an adjustable supply. Decrease the voltage in 0.1 V steps. Record the voltage where the audio stops.
- If the EarPods operate at 3.3 V, a hardware change (pin 18 to VBUS through a switch) is possible. Else a 3.3 V to 5 V step-up converter is necessary.

## The tests

| Version | Device | Result | Conclusion |
|---|---|---|---|
| 0.1.56 | 3-in-1 adapter, card reader | Host mode tone. Photo import: "unsupported device", with and without a card. | Host mode starts. The card is not the cause. |
| 0.1.59 | Dock | Log: only the simulated root hub (05AC:8031). | No device reached a driver. |
| 0.1.60 | Dock | VBUS valid, connection, reset, high speed, transfers running. No driver call. | The hardware path works. |
| 0.1.61 | Dock | Full speed forced. The same result. | Speed is not the cause. |
| 0.1.62 | Dock | The probe stopped after the first tone. | A read in the 0x90000000 window stops the real iPod (the emulator allows it). Fixed in 0.1.63. |
| 0.1.63 | Dock | The first qTD to the dock completed (token 0x8D00, no error), but no next request. | The "transfer done" interrupt did not reach the host stack. |
| 0.1.64 | Dock | Device handler removed. GET_DESCRIPTOR 8, SET_ADDRESS, GET_DESCRIPTOR 18: the dock's hub descriptor. Then a stop. | The interrupt fix works. |
| 0.1.66 | Dock | All three stages of the 18-byte read completed correctly. Then the hub driver went back to its port poll. | The stop is a decision in the software, not a transfer error. |
| 0.1.67 | Dock | "Add device" for the dock's hub 2109:2817 → hub driver validate and initialize. Configuration, SET_CONFIGURATION 1, hub descriptor, hub status, periodic schedule on. Then the log limits were reached. One long low tone heard (the second came about 1 s later). | The hub policy was the cause. The hub driver runs on the dock's hub. |
| 0.1.68 | Dock, card reader | The dock's hub configured: hub descriptor, GET_STATUS, PORT_POWER on five ports, interrupt endpoint 1 (interval 255) and the status-change transfer. Then no record. The second log write is missing. | The hub works up to the port power. The port change does not arrive or is not processed. |
| 0.1.69 | Dock, card reader | Both log writes. Interrupt completions only from the root hub. No completion of the dock's status-change transfer in 30 s; no completions for the five PORT_POWER requests. | The dock's transfers stop after the hub status read. |
| 0.1.70 (test A) | Dock, card reader connected from the start | Async QH of the dock's hub (address 51, endpoint 0): token 0x80008D80 = active, IN, 0 bytes, error count 3, data toggle 1: a status stage that waits (probably NAK) without end, probably of the first SET_PORT_FEATURE PORT_POWER. The periodic list has only an empty anchor QH; the dock's interrupt QH is not found. | The control pipe of the dock's hub stops at the status stage of the first PORT_POWER. The status-change endpoint is possibly not in the periodic schedule. Caution: the probe reads through the cached window; the second dump can show old values. |
| 0.1.70 (test B) | Dock; card reader connected after the first double beep | The same as test A: the status stage of the dock's hub stays active, no port change, the periodic scan finds one QH with only zeros. | The time of the connection does not matter. Theory: the periodic list blocks the controller after "periodic on". |
| 0.1.71 | Dock, card reader from the start | Frame list entry 0 = 0x9363B682 (a block of zeros); Apple's table: the dock's interrupt QH at 0x93623080 (address 105, endpoint 1, correct). Experiment: periodic off for 2 s did not change the active PORT_POWER status stage. | **Firmware bug in 0xf5c80**: the frame list gets (r1 + 0x34), but the callers leave the QH only in r0. The status-change endpoint was never polled. The PORT_POWER stall is separate. |
| 0.1.72 | Dock, card reader from the start | **The dock's hub reported its ports. The hub driver reset them, and three devices were enumerated: 05E3:0749 and 2537:1081 (both to the storage driver, class 08/06/50) and 291A:8346 (USB billboard, class 0x11, no driver). The storage driver sent GET_MAX_LUN. Many tones, including the storage sign.** | **The periodic fix was the missing part. The complete chain works: USB-C mod, host mode, external hub, storage.** |
| Probe 0.1.72 (2026-10-08) | Dock; USB-C EarPods on a USB-C port of the dock; card reader removed | The dock's hub enumerated again (address 105). Port 2: **05AC:110B (the EarPods), class EF/02/01**, address 106. "Add device" ran, and then no driver call came. Port 3: the dock's own card slot 2537:1081 to the storage driver. Port 5: the billboard 291A:8346, no driver. The hub interrupt QH (S-mask 0x01, C-mask 0x1C) stays in frame 0. | The EarPods operate on the 5 V of the dock and answer at full speed. The firmware has no driver for device class 0xEF: the composite driver takes only class 0. |
| 0.1.79 | Dock; USB-C EarPods; card reader removed | "Add device" gave the EarPods (05AC:110B) to the composite driver (validate, initialize device). The driver read three configurations (4-byte reads: 165 and 500 bytes for numbers 2 and 3) and the full configuration 1 (430 bytes), then sent SET_CONFIGURATION 1 and SET_FEATURE 1 (remote wakeup). No interface driver (audio, HID). The log was full (511 records) before the second write. | **The EarPods are a UAC2 device at full speed with a synchronous OUT endpoint.** The data dumps of configurations 2 and 3 were not correct (the cache, refer to cause 6). |

## The causes found

1. **No host mode without a Camera Connector.** The stock firmware starts the host stack only after iAP lingo 6 with a Camera Connector (0x1fb50c). The probe calls the host start 0x2860e8 directly.
2. **The USB interrupt belongs to the device driver.** The device driver installs its handler 0xcd8e0 for source 20 after each start. The UIM install of 0xffd1c (0x9741c) then has no effect. The probe removes the device handler (0x127888, 0x1277d0), installs 0xffd1c (0x18a83c) and enables the source.
3. **External hubs are refused** (fixed in the probe; the dock's hub then works). In "add device" 0xd377c, a device of class 9 is accepted only if `g[0] > 1`, or if `g[1] < 3` and (`g[0] != 0` or `g[1] == 0`). g is the USB global block (RAM 0x1083e0f8); g[1] counts the loaded hubs (the root hub makes it 1). g[0] is 0 from the start, and no code sets it. The refusal reports error 0x673 or 0x67d (0xd9cec), and the photo import screen says "unsupported device". The probe sets g[0] = 2.
4. **Firmware bug in the periodic insert** (0xf5c80): the frame list word comes from r1, but the callers give the queue head in r0. No interrupt endpoint (for example the status change endpoint of a hub) is polled. The probe sets r1 = r0 at both calls (0x9761c, 0x96d14).
5. **The emulator allows reads that the real iPod does not.** A read in the 0x90000000 window (the uncached view of the RAM, RAM | 0x80000000) stopped the probe on the real iPod. Read RAM only through 0x10000000–0x14000000.

6. **The probe reads DMA buffers through the data cache.** The probe reads RAM through 0x10000000, and the cache keeps the lines. When the controller then writes new data to the same buffer, the probe reads the old lines. Example: the composite driver put configurations 2 and 3 into the same buffer as configuration 1, and the dumps showed old bytes. The firmware itself reads through the 0x90000000 window and gets correct data. Only the first read of a buffer is reliable.

## The USB-C EarPods (05AC:110B)

Device descriptor: USB 2.01, class EF/02/01, packet size 64, three configurations. Configuration 1 (430 bytes, 5 interfaces, bus power 300 mA, remote wakeup):

| Interface | Alternate | Contents |
|---|---|---|
| (association) | | Interfaces 0–2, class 01/00/20: USB Audio Class 2 |
| 0 | 0 | Audio control (01/01/20). Clock sources 9 and 10 (attributes 7: internal, programmable). Interrupt endpoint 0x81 IN, 6 bytes, interval 1. |
| 1 | 0 | Playback, no bandwidth |
| 1 | 1 | Playback: PCM, 2 channels, 24 bits in 3 bytes. Endpoint 0x02 OUT isochronous, **synchronous**, 288 bytes, interval 1 (48 samples each 1 ms = 48 kHz) |
| 1 | 2 | Playback: PCM, 2 channels, **16 bits** in 2 bytes. Endpoint 0x02 OUT isochronous, synchronous, **192 bytes** (48 kHz) |
| 2 | 1, 2 | Microphone: 1 channel, 16 or 24 bits. Endpoint 0x83 IN isochronous, 96 or 144 bytes |
| 3 | 0 | HID (report 31 bytes). Endpoint 0x85 IN interrupt, 64 bytes |
| 4 | 0 | HID (report 42 bytes). Endpoint 0x86 IN interrupt, 64 bytes |

Results for Stages 2 and 3:

- The OUT endpoint is synchronous. Thus the iPod sends a fixed number of samples in each frame (1 ms), and no feedback endpoint is necessary.
- The simplest format is interface 1, alternate 2: 16 bits, 2 channels, 192 bytes each frame at 48 kHz. At 44.1 kHz: 44 or 45 samples (176 or 180 bytes) each frame.
- The sample rate is set with a UAC2 request (SET_CUR, sampling frequency) to the clock source. The probe did not read the rate range (UAC2 GET RANGE).
- An external test ([Mac Otakara](https://www.macotakara.jp/accessories/entry-45311.html), on a Mac) gives the same product ID 0x110B, full speed (12 Mbps) and the rates "16 bit/44.1 kHz to 24 bit/48 kHz" for playback and for the microphone. Thus the EarPods probably accept 44.1 kHz. Then the iPod can send its music without a rate conversion: 44 or 45 samples each frame. The firmware version is 26.81.
- The host stack must make isochronous transfers (Stage 2). At full speed through the hub, the controller uses split transactions (siTD), as for the hub's interrupt endpoint (C-mask 0x1C).
- The HID interfaces are probably the buttons of the remote (volume, play). They are not necessary for audio.

## Key addresses (osos 1.3)

| Address | Function |
|---|---|
| 0x2860e8 | Host start (UIM init, tasks) |
| 0x97300 | UIM init; 0x97364 chip check (full speed if 0); 0x9741c interrupt install |
| 0x6c8820 | UIM dispatch table; isochronous entries 0x6c885c/0x6c8860 are stubs |
| 0x6bc3dc | Class driver registry (44-byte entries; count at g + 0x1c) |
| 0xd377c | "Add device": the driver selection for a new device |
| 0xc50ac | Driver score: vendor ID 1000, device class 100 (+0x35 of the record), subclass 110 (+0x36) |
| 0x1084a360 | The second composite driver record (class 2). The probe changes it to EF/02. |
| 0xcb118 | Completion callback of a control transfer stage |
| 0xe7980 | Root port status |
| 0x18a83c, 0x127888, 0x1277d0 | Interrupt: install, disable, remove |
| 0xcd8e0, 0xffd1c | Interrupt handlers: device driver, host (UIM) |
| 0x1083e0f8 | USB global block g (byte 0: hub policy, byte 1: hub count) |

## The probe log

Records in `iPod_Control/iTunes/iPodFirmUSBLog` (511 records, 32 KB). iPodFirm shows it ("Show USB Log", "Copy Log"):

- the class driver calls (validate, initialize device, initialize interface),
- "add device" with the device descriptor,
- the UIM calls (create control endpoint, control transfer with the setup packet),
- the completions of the device transfers,
- the root port status changes,
- the controller registers and the transfer queue,
- the interrupt install steps,
- the queue heads and Apple's periodic table,
- the received bytes of each configuration descriptor, decoded (interfaces, endpoints, audio class descriptors).

## Next steps

1. Done: the configuration of the EarPods (UAC2, refer to "The USB-C EarPods").
2. Optional: read configurations 2 and 3 and the clock ranges (UAC2 GET RANGE). The external test above makes this less important: the Stage 3 driver can try 44.1 kHz and use 48 kHz if the EarPods refuse it. The probe must read each buffer only one time, or clean the cache first.
3. Optional bench test of the minimum voltage of the EarPods (refer to the hardware section).
4. Then Stages 2 and 3 of USB-AUDIO-OUT.md: the isochronous UIM entries and a USB audio class driver.
