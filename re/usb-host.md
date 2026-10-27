# The USB host stack in osos 1.3

## Goal

USB-C audio out: the iPod as USB host to USB-C headphones and USB DACs. The plan is in [USB-AUDIO-OUT.md](../USB-AUDIO-OUT.md). This note records the research in the sequence of the work.

Offsets are osos image offsets. The CPU address of the code is the same. For RW data, the RAM address is the image offset + 0x10181d5c (see "RW data").

## RW data

The table at 0x8406c gives the RW data copy: image 0x67e2a8, RAM 0x10800004, size 0x4b7a8. The start code copies this area to RAM. The code uses the RAM addresses. Thus a search for an image offset in this area finds no reference. Search for the RAM address.

To change RW data, patch the image at its offset. The start code copies the change to RAM.

## The stack

The stack comes from the Mac OS 9 USB family. Apple used it for the iPod Camera Connector.

| Address | Function | Evidence |
|---|---|---|
| 0x6bc3dc | The class driver list (RAM 0x1083e138): pairs (driver record, dispatch table). Hub, SampleStorageDriver, ICAType4CameraDriver, PTPCameraDriver. | Static (word search, record contents) |
| 0x6c86e8, 0x6c8740, 0x6c8898, 0x6c88f0 | Driver records with the tag "usbd" (Mac OS 9 `USBDriverDescription`): match values and a Pascal name. Hub: class 9. SampleStorageDriver: class 8. ICAType4CameraDriver: vendor 0x04A9. PTPCameraDriver: class 6, subclass 1, protocol 1. | Static |
| 0x6c8728, 0x6c8780, 0x6c88d8, 0x6c8930 | Driver dispatch tables, version 0x1100. | Static |
| 0x6c8820 | The UIM (host controller driver) dispatch table, version 6. | Static (function contents) |
| 0x97300 | UIM init. Clocks on, controller reset (0xd1288), periodic frame list (0x400, 0x200 or 0x100 entries), CONFIGFLAG = 1, run. | Static |
| 0x97228 | UIM finalize. | Static (table) |
| 0x96f64, 0x96ffc | Control endpoint create, control transfer. | Static |
| 0x96d38, 0x96db0 | Bulk endpoint create, bulk transfer. | Static |
| 0x974ec, 0x9762c | Interrupt endpoint create (calls the QH builder 0xead78), transfer (qTD token 0x8c80). | Static |
| 0xd4820, 0xd4828 | **Isochronous endpoint create and transfer: stubs `mvn r0,#0; bx lr` (return -1).** Table words at 0x6c885c and 0x6c8860. | Static (raw bytes `00 00 e0 e3 1e ff 2f e1`) |
| 0xd1288 | Controller reset: USBCMD (0xC5000140) stop, `USBMODE` (0xC50001A8) = 0, reset, wait, then `USBMODE` = 3 (host). | Static |
| 0x11117c, 0x10bd58 | Root hub simulation: GET_DESCRIPTOR. | Static |
| 0xd26b0 | Root hub request dispatcher. Port functions 0x967cc–0x96b48. | Static |
| 0x2860e8 | **Host start.** Starts the UIM (table + 4), registers it (0xb7f18), and makes the tasks "USBStatusTask" and "USBTaskTimeTask". | Static |
| 0x28608c | Host stop. Calls the UIM finalize (table + 8). | Static |
| 0x1422c0, 0x142298 | Accessory methods (vtable 0x668580, slots 0x30 and 0x3c): first 0x1fb50c, then host start or host stop. They set the state +4 to 3 (host on) or 5 (host off). | Static (ListVtable) |
| 0x1fb50c | Sends an iAP packet, lingo 6 (USB host), command 3, with 1 (on) or 0 (off), and waits for the answer. With no accessory, it returns 0xb at once. 0x1422c0 does not examine the result. | Static |
| 0x2856a4 | `USBPowerSense` task. When USB power is present (0x264c34), it runs the USB device session (0x163ffc). | Static |

## How the stock firmware enters host mode

1. A Camera Connector identifies itself with iAP lingo 6.
2. The accessory object calls slot 0x30 (0x1422c0).
3. 0x1fb50c tells the accessory over iAP to switch to host mode. The accessory switches its own circuit. It probably also supplies the 5 V for the camera.
4. 0x2860e8 starts the host stack. The UIM init sets `USBMODE` to host (0xd1288).

Thus the iPod does not make the 5 V for the USB device itself. On a USB-C mod there is no iAP accessory, so the stock firmware never enters host mode. A flash drive on an OTG adapter cannot show a result with the stock firmware.

## Consequences for the plan

- The patch can start the host stack itself: call 0x2860e8 (or 0x1422c0, which ignores the missing accessory).
- VBUS must come from outside, for example a USB-C OTG adapter with a power input. Then the iPod also sees USB power, and `USBPowerSense` starts the device session. The patch must stop the device session, or must not start it, when USB Audio Out is On and no computer answers. The firmware already knows a charger from a computer: a charger gives power but no USB reset.
- Stage 0 needs a probe patch, not only the stock firmware. The probe starts the host stack from a menu item and gives a sign (for example a click of the piezo) when the hub driver adds a device (hubAddDeviceHandler 0xe7a50).

## The probe patch (2026-10-06)

`patches/usb-host-probe` (branch `usb-audio-out`) is the Stage 0 test. Refer to [modifications.md](../docs/modifications.md#usb-host-probe).

| Address | Function | Evidence |
|---|---|---|
| 0x1d8260 | `bl 0x1d8570` in the UI event handler. A free hook site for "each event". | Static, Patch |
| 0xcd430 | Piezo tone (pitch, duration in µs). | Static (callers 0x91438, 0x284374) |
| 0x6c8730, 0x6c878c | Driver dispatch entries: hub "initialize device", storage "initialize interface". | Static |

Emulator results:

1. The first version read the trigger file at the first event of any type. That event came at approximately 1.9 s after the start, and the probe did not start the host stack. Now the probe reads the file only at a button or wheel event (types 4, 5, 7).
2. A button push ran the host start 0x2860e8, then 0x97300 and 0xd1288 (markers). The menus worked after this.
3. At the next start, 0x2860e8 did not run: the probe had written '0' to the file.

## The flash error (2026-10-07)

The owner's flash failed: "The code area of usb-host-probe is not empty". The owner uses "Switch on iPod" with the "Dark Gray" theme. Its switch table has the data of 4721 changes (approximately 680 KB) and ends at approximately 0x7ea700. The menu and the dark-mode code come after the table. Thus they used the fixed probe address 0x7e8000. Now the probe uses `"load_address": "extended"`, and the build puts it after all other data. The Swift test `testExtendedPatchAfterSwitchBuild` builds this case with a real theme file (`IPODFW_THEME`).

## The demonstration (2026-10-07)

The owner asked to hear the tones before the test. The probe now plays the hub sign and the storage sign one time, then three short beeps and 2 s of silence, then it starts the host stack. Emulator times: demonstration at 31.44 s and 33.08 s, beeps at 35.06, 35.47 and 35.88 s, host start at 38.33 s, UIM init at 38.34 s, and a real hub sign at 38.36 s. Thus `hook_hub_init` operates: the hub driver initializes the simulated root hub, also without USB hardware. The iPod did not restart during the 7 s sleep in the UI task.

## The first real test and the log (2026-10-07)

Real iPod with the 3-in-1 adapter (USB-C plug, USB-A socket, 3.5 mm jack, PD charging) and a USB card reader:

- The host mode sign (one long low tone) came. Thus the patch starts the host mode on the USB-C mod.
- The photo import screen showed "unsupported device" (string 17037), with and without a card in the reader. Thus the import function did not recognise the reader. The card (128 GB SDXC, FAT32, photos in `DCIM/100NIN03`) is not the cause.
- No second long low tone and no storage sign. Thus the hub driver did not initialize a hub in the adapter, and the storage driver did not initialize the reader.

The import status strings: 17033 "ready to connect", 17034 "connecting...", 17035 "connection failed", 17036 "no card inserted", 17037 "unsupported device", 17044 "Unknown format".

The probe now logs each call of the six class drivers (entries 1–3 of each dispatch table) and writes the log to `iPodFirmUSBLog`. iPodFirm shows it ("Show USB Log"). Emulator: two records for the simulated root hub (05AC:8031, class 09).

## No log on the real iPod (2026-10-07)

The trigger file contained '0' after the test, thus the probe ran. The log file contained only zeros. Causes:

1. The probe wrote the log at a later button event. 0x1d81cc gives each event to the active modal screen first (0x12d890, 0x12ddb8) and returns if the screen takes it (branch at 0x1d8254). The photo import screen probably took the events. The emulator showed no import screen, thus the emulator test worked.
2. Emulator: a file write reaches the disk only later. With a stop 5 s after the write, the file had zeros. After 90 s, it had the log.

Fix: 10 s after the host start, the probe writes the log in the UI task, flushes the disk cache (0x1a0120, 0x19ff0c) and gives two short low beeps. Emulator: the log was on the drive 5 s after the beeps.

## The second real log (2026-10-07)

With the dock (a hub), the log had only "Hub: validate" and "Hub: initialize device" for the simulated root hub 05AC:8031. No driver got a device from the USB-C port.

In the emulator, the host start runs and the root hub request handler 0xd26b0 runs four times (descriptor requests), but the port status function 0xe7980 never runs: the hub driver waits for a status-change interrupt, and the emulator has no USB controller. The real log looks the same. Thus possibly the controller on the real iPod also did not report a connection, or its interrupts did not arrive.

The probe now logs:

- each change of the root port status (hooks at 0xd28f0 and 0x10e75c, calls of 0xe7980);
- the controller registers USBCMD (0xC5000140), USBSTS (0xC5000144), PORTSC (0xC5000184) and OTGSC (0xC50001A4), after the host start and before each log write.

Emulator: USBCMD = 1 (run), the other registers 0.

## The third real log: high speed (2026-10-07)

With the dock and the card reader, the new log showed:

| Record | Meaning |
|---|---|
| OTGSC 0x006F4E00 | VBUS valid, A-session and B-session valid: the iPod sees the 5 V. |
| Port status 0x0101, change 0x0001 | A device connected. |
| Port status 0x0503, change 0x0012 | After the reset: connected, enabled, power, high speed. |
| PORTSC 0x28001205 at the end | Connected, enabled, power, PSPD = 2 (high speed), no PFSC. |
| USBCMD 0x00080B21, USBSTS 0x00008084 | Run, asynchronous schedule on and running (control transfers). |

No driver call came. Thus the hardware path works (the USB-C mod, VBUS, connection, reset, high-speed chirp), but the descriptor transfer after the reset failed. The many port records only differed in the line state bits 11:10, which change during high-speed traffic. The probe now ignores these bits.

Hypothesis: the UIM of the Camera Connector (2005) does not handle high-speed devices correctly. The UIM init has a full-speed path (PFSC) for the other chip type. The probe now uses it (hook at 0x97364). If the descriptors then arrive, high speed is the cause. USB audio needs only full speed.

## The fourth real log: full speed (2026-10-07)

With the full-speed hook, the dock connected at full speed (PFSC set, PSPD = 0), the reset worked and the port was enabled. The asynchronous schedule ran. No driver call came. Thus the speed is not the cause. The owner disconnected the dock after the double beep; the later records come from a log write at a later button press.

Hypothesis: the charger in the adapter also gives VBUS to the iPod. Thus the USB device function of the iPod (USBPowerSense) possibly runs at the same time and takes the controller interrupts. USBSTS never showed "transfer done" (bit 0).

The probe now also logs the UIM calls "create control endpoint" and "control transfer" (word hooks at 0x6c882c and 0x6c8830) and a queue record (USBINTR, ASYNCLISTADDR, FRINDEX, the first queue head and its qTD token). Emulator: the root hub gets GET_DESCRIPTOR (device, 18 bytes), SET_ADDRESS 0x30, GET_DESCRIPTOR (configuration, 4 bytes). A control transfer is three UIM calls (setup, data, status); r1 = 0xcb118 is the completion function; the buffers are in the uncached RAM window (0x93b5xxxx).

## The probe stopped (version 0.1.62, 2026-10-07)

The owner heard one tone, then the photo import screen showed at once. No double beep. The trigger file had '0' (the probe started), and the log file still had the old log. The owner's exact build (Switch on iPod with Dark Gray, five patches, version 1.3.1abhsw) worked in the emulator.

Probable cause: version 0.1.62 read the USB buffers in the window at 0x90000000, where the emulator showed them. The emulator allows the read; the real iPod possibly gives a memory fault. Then the UI task stops the probe and continues, thus the import screen shows at once. Fix: read the same RAM through 0x10000000 (address minus 0x80000000). Emulator with the owner's build: correct, with the setup packets in the log.

Lesson: the emulator allows memory reads that the real iPod possibly does not allow. Read only in the window 0x10000000–0x14000000 (64 MB on the owner's iPod).

## The fifth real log: the transfer completes (2026-10-07)

Version 0.1.63 with the dock at full speed. The root hub was set up completely (GET_DESCRIPTOR, SET_ADDRESS 35, configuration, SET_CONFIGURATION, hub descriptor). The 20 UIM records were all used by the root hub, thus the dock transfers are not in the log. The queue record after the reset:

| Field | Value | Meaning |
|---|---|---|
| ASYNCLISTADDR | 0x9362B000 | The first QH, in the uncached window (RAM | 0x80000000) |
| QH word 1 | 0x0840C000 | Address 0, endpoint 0, full speed, maximum packet 64, head of the list |
| qTD token | 0x00008D00 | Not active, no error, 0 bytes left, PID IN, interrupt on complete |
| USBINTR | 0x0B | Transfer done, error and frame-list rollover interrupts enabled |
| USBSTS | 0x8084 | "Transfer done" (bit 0) is clear |

Thus the dock answered the first GET_DESCRIPTOR, and the hardware completed the transfer, but the host stack never sent the next request (SET_ADDRESS). An interrupt handler cleared bit 0, but the host stack did not get the completion.

The USB interrupt (source 20) has two handlers: the device driver installs 0xcd8e0 (0x220e0c), and the UIM init installs 0xffd1c (0x9741c). The interrupt manager is outside the image, thus its rule for two handlers is not known. In the emulator, the device handler is installed after the start, also without VBUS.

The probe now removes the device handler and installs the host handler (hook at 0x9741c), and logs each step. It also skips the root hub transfers in the log. Emulator: disable 1, remove 1, install 0, enable 0; the menus work. The meaning of these results is not known.

## The sixth real log: the dock answers (2026-10-07)

Version 0.1.64 removed the device handler of the USB interrupt and installed the host handler (results: disable 1, remove 1, install 0, enable 0). Then the dock, at full speed:

1. GET_DESCRIPTOR (device, 8 bytes) at address 0, data, status: correct.
2. SET_ADDRESS (the log shows the old setup bytes), then "create control endpoint" at address 101.
3. GET_DESCRIPTOR (device, 18 bytes) at address 101: `12 01 10 02 09 00 00 40` = USB 2.1, class 09 (hub), packet size 64.
4. Then no further request, and no "Hub: validate" for the dock. The last qTD completed (token 0x8D00).

Thus the interrupt fix works: the host stack now gets the completions. The stop after the device descriptor has another cause. Possibly the driver selection needs the Camera Connector session (the accessory object, vtable 0x668580, state 3), which the probe does not start.

The probe now logs each call of the completion callback 0xcb118 (a `b` hook), with the status and the request block, and the log has 127 records (8 KB). Emulator: the root hub completions have status 0.

## The seventh real log (2026-10-07)

The dock sequence was the same (GET_DESCRIPTOR 8, SET_ADDRESS 44, GET_DESCRIPTOR 18 with the hub descriptor, then no more requests). The 40 completion records were all used by the root hub: its status poll ends in a completion all the time (all with status 0). Thus the probe now logs only the completions of the request blocks of logged device transfers.

## The eighth real log: the hub policy (2026-10-07)

All three stages of the dock's 18-byte GET_DESCRIPTOR completed correctly (completion callback, status 0). Then the hub driver used the same request block for the root hub port poll again. Thus the stop is a decision.

"Add device" 0xd377c (text "Add device: VID %d PID %d") refuses a hub after the root hub, unless g[0] (RAM 0x1083e0f8) is not 0. g[0] is 0 in the image, and no code sets it. Error 0x673 or 0x67d goes to 0xd9cec, and the photo import screen says "unsupported device". The probe now sets g[0] = 2 and logs "add device" (hook at 0x10c1d8). Emulator: g = 0x01000102 after the start (g[0] = 2, g[1] = 1); the root hub goes through "add device" to the hub driver.

The complete picture is in [patches/usb-host-probe/FINDINGS.md](../patches/usb-host-probe/FINDINGS.md).

## The ninth real log: the dock's hub is accepted (2026-10-07)

With g[0] = 2, "add device" offered the dock's hub (2109:2817, VIA Labs VL817) to the hub driver: "Hub: validate", "Hub: initialize device". The hub driver read the configuration descriptor (25 bytes), sent SET_CONFIGURATION 1, read the hub descriptor and the hub status, and started the periodic schedule (USBCMD bit 4) for the status-change interrupt endpoint. The log then reached its limits (30 UIM records, 40 completions), thus the port steps of the dock's hub are not in the log.

The probe now takes a 32 KB log buffer (511 records) from the allocator 0x25a974, logs the UIM interrupt endpoint and interrupt transfer calls, and writes the log at 10 s and again at 30 s.

## The tenth real log: the ports of the dock (2026-10-08)

The hub driver configured the dock's hub completely: SET_CONFIGURATION 1, the hub descriptor, GET_STATUS, then SET_FEATURE 8 (PORT_POWER) five times, then "create interrupt endpoint" (address 29, endpoint 1, interval 255) and the interrupt transfer for the status changes (callback 0xcba54). After that, no record: no port change of the dock's hub, thus no port reset and no "add device" for the card reader. The log has only the first write (the second write at 30 s is missing).

Open: does the dock's hub report a port change (an interrupt completion), and is it processed? The probe now logs the interrupt completion callback 0xcba54 (a `b` hook) and clears each record before use (the allocator does not clear the buffer: record 3 showed old text).

## The eleventh real log: no report from the dock's hub (2026-10-08)

Both log writes came. The interrupt completions (records 9, 12, 50, 100) all belong to the request 0x9361CCB0, the status pipe of the simulated root hub. The status-change transfer of the dock's hub (request 0x9361BF50, address 5, endpoint 1) did not complete in 30 s. The five SET_FEATURE PORT_POWER requests to the dock's hub have no completion records either, although each request before them had one.

Possible causes: the asynchronous queue head of address 5 stopped (halted, or still active), or the periodic queue head of the interrupt endpoint is not polled correctly (full speed through the forced-full-speed root port: the split fields and the S-mask matter). The probe now logs each asynchronous and periodic queue head with its state before each log write.

## Test A with the queue dump (2026-10-08)

Async QH 0x93623040 (address 51 = the dock's hub, endpoint 0, full speed, packet 64, hub 0 port 1): overlay token 0x80008D80 = active, IN, 0 bytes, error count 3, data toggle 1, interrupt on complete. Thus a status stage of a control request without data stays active: the hub probably answers NAK without end. It is probably the first SET_PORT_FEATURE(PORT_POWER); the five PORT_POWER requests had no completions. The periodic frame list had only one QH, an empty anchor (all words 0); the interrupt QH of the dock's hub was not found. The probe reads through the cached window (0x1xxxxxxx), thus the values of a second dump can be old.

## Test B (2026-10-08)

The card reader was connected after the first double beep. The result is the same as test A: the status stage of the dock's hub (address 87) stays active, and no port change comes. The periodic scan again found one queue head with only zeros (0x90AB0680).

Theory: the transfers to the dock completed until the periodic schedule was switched on (after "create interrupt endpoint"). If the periodic list has a link of 0, the controller follows it to address 0 in each frame and possibly never gets time for the asynchronous list. The UIM keeps for each queue head the processor address and, at +0x34, the controller address (processor address | 0x80000000); thus the probe reads the same memory as the UIM.

The probe now logs Apple's own periodic table (frames 0–7) and does an experiment: after the first log write, it switches the periodic schedule off for 2 s and logs the queues again. Emulator: the frame list holds 1 (terminate) in each frame, and no queue heads.

## The periodic schedule bug (2026-10-08)

Version 0.1.71 with the dock and the card reader from the start:

- Frame list entry 0: 0x9363B682, a QH pointer to 0x9363B680, which holds only zeros.
- Apple's own table for frame 0: the QH at 0x93623080. Its words: link 0x00000001, endpoint characteristics 0x00010169 (address 105 = the dock's hub, endpoint 1, full speed, 1 byte), S-mask 0x01, C-mask 0x1C, its controller address at +0x34 = 0x93623081, interval byte 0x7F. Thus the QH is correct, but the frame list points to the wrong address.
- The cause: 0xf5c80 makes the frame list word from `(r1 + 0x34) | 2`. At 0x9760c, "create interrupt endpoint" loads r1 = the UIM controller object (for a compare of +0x5e) and calls 0xf5c80 with the QH only in r0. The other caller (0x96d14) also leaves r1 unset. The frame list therefore pointed to the controller object +0x34. This is a firmware bug. With the Camera Connector, it was probably not seen: cameras use bulk transfers, and the root hub status pipe is simulated.
- The experiment (periodic schedule off for 2 s) did not change the active status stage of the dock's hub. Thus the PORT_POWER stall has another cause, or the controller stays stopped after the bad periodic access.

Fix in the probe: a wrapper at 0x9761c and 0x96d14 sets r1 = r0 and continues in 0xf5c80.

## The periodic fix works (2026-10-08)

Version 0.1.72 with the dock and the card reader from the start. Frame list entry 0 = 0x93623082 (the dock's hub interrupt QH, address 83). The hub sent its first port report, the PORT_POWER requests completed, and the hub driver read the port status (GET_STATUS 4 bytes), cleared the change bits (CLEAR_FEATURE 16, 20) and reset the ports (SET_FEATURE 4). Three devices were enumerated:

| Device | Class | Result |
|---|---|---|
| 05E3:0749 (Genesys Logic) | 0, interface 08/06/50 | Composite driver, then "Storage: initialize interface"; string descriptors; GET_MAX_LUN (A1 FE) |
| 2537:1081 (Norelsys) | 0, interface 08/06/50 | Composite driver, then "Storage: initialize interface" |
| 291A:8346 | 0x11 (billboard) | "Add device", no driver |

The bulk QHs (endpoints 1 and 2) of both storage devices are in the asynchronous list. Thus the PORT_POWER stall of the earlier tests was a result of the periodic bug. The complete chain works: USB-C mod, host mode, external hub, storage.

## The USB-C EarPods through the dock (2026-10-08)

Probe 0.1.72, the dock with its power supply, the USB-C EarPods on a USB-C port of the dock, the card reader removed.

- The dock's hub (2109:2817) got the address 105. Its interrupt QH is in frame 0 and operates.
- Hub port 2: the EarPods. Port status 0x0103: connected, enabled, power, full speed. Address 106.
- Device descriptor: `12 01 01 02 EF 02 01 40`: USB 2.01, class 0xEF, subclass 2, protocol 1 (interface association), packet size 64. ID 05AC:110B.
- "Add device" 0xd377c ran for the EarPods. No validate call to a class driver followed. Thus no driver in the registry 0x6bc3dc accepts device class 0xEF.
- Hub port 3: 2537:1081 (the dock's card slot) to the storage driver. Hub port 5: the billboard 291A:8346, no driver.

The class 0xEF with an interface association is normal for USB audio devices, and especially for UAC2. The configuration descriptor was not read. Thus the audio class version, the alternate settings and the sample rates are not known yet.

## The driver selection for class 0xEF (Ghidra, 2026-10-08)

"Add device" 0xd377c scores each registry entry with 0xc50ac and calls the validate of the best entry.

- The vendor ID equal to the record +8: 1000 points.
- The device class equal to the record +0x35: 100 points. The subclass equal to +0x36: 110. The protocol equal to the u16 at +0xe: 10 more.
- The registry 0x6bc3dc has two composite entries with the same dispatch 0x1084a348. The record 0x1084a308 has class 0. The record 0x1084a360 has class 2 (communications).
- The composite validate 0x108b6c returns 0 for each device.

No entry matches class 0xEF. Thus the EarPods got no driver. The probe now changes the class bytes of the record 0x1084a360 to EF/02 before the host start. The EarPods then get 110 points and the composite driver. The probe also logs the received bytes of each GET_DESCRIPTOR configuration request. Emulator: the host start and both log writes are correct (the emulator has no USB device).

## The configuration of the USB-C EarPods (2026-10-08)

iPodFirm 0.1.79, the dock with its power supply, the EarPods on a USB-C port of the dock.

- "Add device" gave the EarPods to the composite driver (the probe changed the record 0x1084a360 to EF/02). The composite driver sent GET_DESCRIPTOR configuration 4 bytes for numbers 1 and 2 (totals 500 and 165 bytes), then the full configurations into one buffer, then SET_CONFIGURATION 1 and SET_FEATURE 1 (remote wakeup).
- No interface driver accepted the audio or HID interfaces. That is the expected result.
- Configuration 1 (430 bytes, the bytes of the first dump): an interface association for interfaces 0–2, class 01/00/20 (UAC2). Interface 0: audio control, clock sources 9 and 10, interrupt endpoint 0x81. Interface 1: playback, alternate 1 = 24 bits (endpoint 0x02, 288 bytes), alternate 2 = 16 bits (endpoint 0x02, 192 bytes). Interface 2: microphone, endpoint 0x83. Interfaces 3 and 4: HID, endpoints 0x85 and 0x86.
- Endpoint 0x02 has the attributes 0x0d: isochronous, synchronous. The interval is 1 (each frame).
- The dumps of configurations 2 and 3 were not correct. The composite driver put them in the same buffer, at +430. The probe had read that memory one time already, and the cache kept the old lines.

Raw bytes of configuration 1: refer to the log file copy of the owner (iPodFirmUSBLog, records 379–391).

## Stage 2: the isochronous test (Ghidra and emulator, 2026-10-09)

The UIM has no isochronous transfers, thus the probe (version 1.2) makes them without the UIM. The facts from Ghidra:

- 0xad80c(size, 1) gives the memory of the UIM. The frame list (0xe5540) and the queue head pool (0xe4238) come from it.
- 0xa7164 (the cache operation for a buffer) is empty, and 0x9e2d4 (the physical address) gives the same address back. Thus the CPU and the controller use the same address in the window 0x9xxxxxxx.
- A queue head of the UIM keeps the controller address at +0x34. Real logs: it is equal to the queue head address. Thus the stop of version 0.1.62 was probably a read at a bad address, not a read in this window.
- The frame list has 1024 entries (USBCMD bits 3:2 = 0, controller object +0x5c = 0x400). An empty entry is 1. The UIM puts an interrupt queue head into the frames offset, offset + interval, and so on.
- The full-speed queue heads of the UIM use hub 0, port 1 (the transaction translator in the controller). The interrupt queue head of the dock's hub uses S-mask 0x01 and C-mask 0x1C.

The test: refer to [docs/modifications.md](../docs/modifications.md#usb-host-probe), item 16. Each frame gets an siTD: OUT, hub 0, port 1, S-mask 0x03, total 192 bytes, TP "begin", T-count 2. The siTD is before the old entry of the frame. The control requests use a queue head of the probe after the queue head in ASYNCLISTADDR.

Offline test: the device finder `find_audio`, compiled for the Mac, found address 116, interface 1, alternate 2, endpoint 2, 192 bytes and clock 9 in the EarPods log of 2026-10-08.

Emulator (a variant with these values forced): the memory was at 0x93B53000 and 0x93B4A740, the frame list at 0x93B59000. ASYNCLISTADDR is 0 in the emulator, thus the guard stopped the control requests. The siTDs were linked for 5 s and removed. The second log write came, and the menus worked.

## The first tone test did not start (probe 1.2, 2026-10-09)

The EarPods enumerated and the composite driver read the configurations, as before. No audio record was in the log, and no tone came.

- The log had 511 records (full) before the audio test.
- The dump of configuration 1 began with 16 zero bytes. The probe had read the same buffer before (the three 4-byte reads), through the 0x1xxxxxxx window. The cache kept that line. Thus the device finder (from the log) found no configuration.
- Result: the 0x1xxxxxxx window is in the cache. The 0x9xxxxxxx window is not in the cache, because the firmware reads the same buffers correctly there.

Probe 1.3: it reads 0x9xxxxxxx addresses directly, finds the audio interface in the buffer at the completion, and keeps the last 16 log records for the test. Emulator: correct.

## The first USB audio from the iPod (probe 1.3, 2026-10-10)

The dock with its power supply, the USB-C EarPods on a USB-C port of the dock. The owner heard the 1 kHz tone in the EarPods.

| Record | Value |
|---|---|
| Device | Address 67, interface 1 alternate 2, endpoint 2 OUT, 192 bytes, clock source 9 |
| Memory (0xad80c) | Control page 0x9365A000, siTDs 0x936519A0. Frame list 0x93662000. ASYNCLISTADDR 0x93664380. |
| SET_INTERFACE 1, alternate 2 | Setup token 0x80000E00, status token 0x00000D00: correct |
| SET_CUR sampling frequency 48000, clock 9 | Correct |
| Stream | 5105 frames correct, 0 errors, frame 412 to frame 399 (about 5.1 s) |
| SET_INTERFACE 1, alternate 0 | Correct |

Results:

- The siTD format of the EHCI specification operates on the ARC controller: OUT, hub 0, port 1, S-mask 0x03, T-count 2, TP "begin", 192 bytes.
- A control queue head of the probe in the asynchronous list operates beside the queue heads of the UIM.
- The EarPods accept SET_CUR 48000 Hz on clock source 9.
- The siTDs in all 1024 frames, before the old entries, did not disturb the dock's hub or the storage device.

## Stage 4: the music path (Ghidra, 2026-10-10)

The firmware has a USB audio source for accessories (refer to [usb-audio.md](usb-audio.md)). Its parts:

- The audio output object (0x1a3070, RAM 0x108236a8) gives each decoder buffer to the codec, or to the USB source if +0x5a is 1 (0x1a2d60). +0x5a is +0x58 (USB stream on, 0x1a2fa0) and +0x59 (the route allowed, 0x1e6640 after the iAP conditions 0x1e61c0).
- The USB source object (0x1e30d0, RAM 0x10831964) keeps 6 decoder buffers in a queue and converts the rate (0x1e2de0, 0x1e2f60). 0x1e3064 fills a packet; an empty queue gives silence.
- USBAudioTask (0xc75cc) waits for the event at state + 0x18 (state RAM 0x108234ec), then runs 0x132038: 12 packets, send, wait, give back the earlier set.

The probe 1.4 uses this path without the device side: it sets state + 2, signals the event, sets +0x59 and calls 0x1a2fa0. Hooks on the send and wait calls in 0x132038 put the packets into the siTDs. Emulator: the route and the hooks operate, but the emulator has no audio, thus the packets were silence.

## The music test (probe 1.4 real, 1.5 emulator, 2026-10-10)

Probe 1.4 on the real iPod: SET_INTERFACE and SET_CUR 44100 correct; the route went to USB (+0x5a = 1); 42 204 packets, 0 underruns. But no music: the song stayed at 0:00, the album art did not load, and the menus were slow.

The cause, from the machine code of 0x1e3064: the packet comes from the queue only if source + 0 is 0 and 0x1e2f74 returns 1. Else r3 = 1, and 0x1e2c90 gives silence and leaves the queue. With source + 8 = 0, 0x1e2f74 returns 0 while the byte at 0x1081dff6 is 0. An iAP "Digital Audio" accessory sets this byte. Thus the decoder gave its first 2 buffers, they were never taken, and the decoder waited.

The slow menus: probe 1.4 wrote the 32 KB log at almost each wheel event after 2 s of music.

Probe 1.5 sets 0x1081dff6 = 1, writes the log at most each 5 s of music, and logs the decoder chain. Emulator: the queue indices move (write 5 read 3, then write 1 read 5), 47 packets with sound, and the player went to the next songs. The emulator decodes too slowly for a full stream.

## The music plays (probe 1.5, 2026-10-10)

The owner heard the music in the USB-C EarPods. Status records: 38 892 packets, 0 underruns, 1406 packets with sound; USB buffers 2, the queue moved, ready flag 1, 44 100 Hz without conversion.

The UI was very slow, and the album art in Now Playing did not load. Already in probe 1.4, with the decoder stopped, the UI was slow; thus the cause is in the USBAudioTask loop, not in the decoder. The sleep 0x11c9fc (0xa0df0) is a kernel delay (0x84644 request 0x14), then a loop of 0xa0be0 (the time passed?) and 0xa69b4 (request 0x1c, a yield) until the time is over. The probe called it with 1 ms many times in each 12 ms. Apple's device code blocks on an event of the USB interrupt instead (0xd1e78).

Probe 1.6: one sleep of (frames in front − 24) ms each cycle, and a record of the sleeps and the frames that passed.

## The slow UI (probe 1.6 and 1.7, 2026-10-10)

Probe 1.6 on the real iPod: 1313 sleeps, 14 924 ms requested, 14 991 ms passed: the sleep is exact. But the UI was still slow, the album art did not load, and only 408 of 15 780 packets had sound. The disconnection and connection of the dock froze the iPod.

The sleep 0x11c9fc gives the kernel request 0x14 and then yields (request 0x1c) in a loop until the time is over. The measurement cannot show if the task blocks or yields. Apple's device code blocks on a counting semaphore (0xd1e78 wait, 0xd1e70 signal). The host interrupt handler 0xffd1c clears USBSTS bits 0–1 and posts a message to the UIM task.

Probe 1.7: the last siTD of each set has "interrupt on complete"; a wrapper in front of 0xffd1c signals the endpoint event of the device mode (0x108318ec + 0x14); USBAudioTask waits on that event. A disconnection of the root port, or 200 siTD errors in a row, stops the music and gives the route back to the codec.

## The restart of probe 1.7 (2026-10-10)

The iPod restarted after the tone. The first set with "interrupt on complete" gave a transfer interrupt, and `music_isr` called 0xd1e70 in the interrupt. 0xd1e70 makes a kernel request (0x84644, type 2) when a task waits. The host handler 0xffd1c uses 0xadbdc instead: it puts {function, arguments} into a queue (0x278378), and a task calls the function. Probe 1.8 posts `music_dpc` with 0xadbdc. Emulator: a posted `music_dpc` wakes USBAudioTask.

The owner: the music of probe 1.6 sounded correct. Thus the decoder had enough CPU, and the low count of packets with sound came from the full log (only the first 16 s were logged). Probe 1.8 keeps 96 records for the music.

## The CPU of the music path (probe 1.8 real, emulator profile, 2026-10-10)

Probe 1.8 also restarted the iPod after the tone. The log had the records up to "music route on", thus the restart came after the stream started. The interrupt path is the cause, in 1.7 and 1.8.

The emulator profile (`IPODFW_PROFILE=1`, 15 s of the music route with the 1.6 sleep):

| Block | Part of the instructions | Function |
|---|---|---|
| 0x737840 | 19.2 % | `hook_usb_send` of the probe: the copy with the −12 dB shift |
| 0xc7580 | 5.4 % | USBAudioTask |
| 0x1e2bc0, 0xd3e80, 0xd3e40 | 6.5 % | Apple's packet pool and fill |
| 0xa0bc0, 0xa6980, 0x284080 | less than 1 % | the sleep loop 0x11c9fc |

Thus the sleep blocks, and the cost is the work for each 1 ms packet. Probe 1.9 copies whole 32-bit frames, sets the volume on the EarPods (UAC2 SET_CUR volume, feature unit 2 before output terminal 3) and logs the time of its copy and of Apple's packet fill with the microsecond timer (0x60005010, the base of 0x282860).

## The lag is not in the music path (probe 1.9, 2026-10-13)

Update (2026-10-16): the owner found that a separate patch caused the UI lag, not the USB host probe. The item is closed.

Probe 1.9 on the real iPod: no restart; the music played. The CPU record (the microsecond timer): the copy of the probe 1.1 %, Apple's packet fill 2.8 % of 152 s. Thus the USB audio work is not the cause of the lag.

The byte 0x1081dff6 is not the cause either: in the block at 0x1081dfdc, only the reset (writes 0) and 0x1d56e0 (sets it if a special file exists in `iPod_Control\Device`) use offset 0x1a, and only 0x1e2f74 reads it.

The idle routine 0xded04 keeps the idle microseconds of each core at RAM 0x14983040. Probe 1.10 logs the idle percentage for each phase: before the host start, in host mode, in the tone test and with the music. Emulator: 97.8 % idle in host mode, 97.6 % with the music route (the emulator has no USB traffic). The real values show which phase uses the CPU.

The volume: the EarPods buttons send HID reports to the host; the probe has no HID driver. The iPod volume does not change the USB route. A later patch can map the iPod volume to the feature unit volume (SET_CUR) and the HID buttons to the iPod volume.

## The Now Playing art (probe 1.10 and 1.11, 2026-10-14)

Probe 1.10: scrolling is correct. The UI stutters only when the album art of Now Playing must show, and the art does not show. The album-art patch is not involved (it draws only the covers in the lists).

Hypothesis: in each music test, the card slot of the dock (2537:1081) gets the storage driver, and the iPod enters the photo import state of the Camera Connector ("ready for SD card"). The photo import and the album art use the same image library (ithmb files). Probe 1.11 sets the storage driver record (RAM 0x1084a49c) +0x12 and +0x35 from 8 to 0xff before the host start, thus no storage device gets a driver.

## The Now Playing art: Ghidra (2026-10-15)

Probe 1.11 (no storage driver): the art still does not load. Idle statistics (0xded04, core 0): 96.8 % before the host start, 87.0 % in host mode, 57.0 % with the music route before the song, 26.6 % during the song. The probe's own code is about 4 %.

The art of Now Playing comes from ArtworkLoadTask (the name at 0x2aa7fc, made by 0x205cfc). Its loop 0x205db4:

1. waits on its event at task + 0x4c;
2. a gate for the client 0x19 at the kernel port 0x14: query 0x94bbc; if 0, request 0x94e6c and sleep 1.5 s; the release 0x94d80(0x19, 500) at the end;
3. the lock at task + 0x40 (0xd6a64);
4. the request lookup 0x2065c4 and the artwork lookup in the database 0x1f161c (0 = no art);
5. 0x29e024 and the image load 0x2258a4 and 0x225594.

The port 0x14 server is the task 0x284b0c (45 clients). A query is granted if the power-chip state (0x2651e4) is set or a client is active; during the music the audio client (0x27) is active. No display or artwork code reads the USB audio flags. 0x1a3080 makes the audio output object again and resets the USB route flags.

Probe 1.12 traces each step of the task loop (tags 58–61) and has a mode without the music route ('2'). Emulator: the task wakes, the gate is granted (step 3 result 1), and the release follows; the emulator library has no art.

## The art is missing when the probe is only installed (2026-10-15)

Probe 1.12, run 1 (no music route): ArtworkLoadTask woke 11 times and the gate was granted, but its request queue (task + 0x50) was always empty. 0x20620c fills the queue inside the task loop from the play queue (the singleton 0x196418, vtable 0x66cad4; method +8 0x1968b0 = "the play queue exists"), from the count of 0x2059d0 and from task + 0x78.

The owner: the art does not load when the probe is installed but not started, and it loads when the probe is removed. Thus the cause is static. With the owner's patches ("Switch on iPod" with Dark Gray, album-art, something-comforting) the image ends at about 0x7EE3A0 without the probe and at about 0x7F1D30 with it: above the old limit 0x7F0000. A search for literals that point to 0x7F0000–0x800000 (CPU, physical or DMA window) in the code finds none. Thus a user of that RAM finds the address at run time. Test: the app setting "Layout" with the limit 0x7F0000.

The emulator: the owner's artwork and songs on the emulator drive; the songs did not start from the Songs list, thus no art test there.

## The hooks that run without the probe start (2026-10-15)

The owner: with probe 1.12 the art is missing also when the probe is not started, with each patch set and with both margins. A check of each hook site and its callers: without host mode only `hook_event` (0x1d8260) runs, and in 1.12 also the 14 art-trace hooks and the two `hook_output_make` sites. `hook_event` passes the call to 0x1d8570 (2 arguments, the result not used) and reads the trigger file one time. Probe 1.13 removes the 1.12 hooks; it has the hook set of 1.11.

## The 1.12 trace hooks stopped the art (2026-10-15)

Probe 1.13 (without the 16 hooks of 1.12), installed and not started: the owner sees the Now Playing art again. Thus the trace hooks were the cause when the probe was not started. Probable cause: the code of 0x205db4 uses register values (for example r1 after a call) that it expects the callee to keep; the C wrappers of the trace did not keep them. The art test with the probe started (host mode) is the next step.

## The art in host mode: static analysis (2026-10-15)

The owner: with probe 1.13 and "Start the Probe Without Music", the Now Playing art is missing. All results in this section are from Ghidra (static). The emulator results are not used, because the emulator does not give the same result each time.

The gates of the art load. Each gate must be open for the art to show:

| Gate | Where | Condition |
|---|---|---|
| 1 | 0x20620c | The play queue exists (0x196418, method +8). |
| 2 | 0x20620c | The count of 0x2059d0 is not 0. |
| 3 | 0x20620c | The art object + 0x78 is not 0. |
| 4 | 0x20620c | The budget limit is more than 0. The budget uses the capacity at the art object + 0x74. |
| 5 | 0x205db4 | The task event at the art object + 0x4c is set. |
| 6 | 0x205db4 | The client 0x19 of the keep-awake task 0x284b0c is active. |
| 7 | 0x205db4 | The lookup 0x1f161c finds the art in the database. |
| 8 | 0x205db4 | The image load 0x2258a4 and 0x225594 reads the ithmb file. |

The capacity at + 0x74:

- The library open 0x1bfb94 calls the grant (art object method + 0x10, 0x206b78) for each cache: + 0x74 = 0x100000.
- The library close 0x1bfd18 calls the release (method + 0x14, 0x206b98) for each cache: + 0x74 = 0.
- The open reserves memory with 0x1f15b0 (pool at library + 0x38). The close gives it back with 0x1f16c4.

The callers of the library close:

| Caller | Condition | Open again after |
|---|---|---|
| 0x1ed828 (from 0x1ee8d0) | 0x1ee8d0 with a second argument that is not 0 | Yes: 0x1ee8d0 then calls 0x1ed918, and 0x1ed918 calls the open 0x1bfb94. With the argument 0, no close occurs. |
| 0xb4fe4 (from 0x1ec2c8) | The database reload, if the app + 0x1c is not 0 | Not in the same function |
| 0x16e85c (from 0x16f3e4) | The event type 0x10 with the identifier 0x5381 | Not in the same function |
| 0xb2dc8 (from 0x1919d8) | A change of the byte + 0xb54 of the database | Yes, when the byte changes to not 0 |
| 0x201b4c | The image view starts | 0x201c18 |

This corrects an earlier note: the path 0x1ee8d0 does not leave the library closed.

The photo import object:

- The start table entry at 0x69ce28 calls 0x19a48c. 0x19a48c makes the object with 0x19b198 and keeps it at RAM 0x1081e97c.
- 0x19b198 sets the state byte + 0x1c to 1 and registers the service 0x4280.
- 0x19b014 changes the state. The callers set 5 (0x19a5ac), 6 (0x197c24), 0xa (0x197e08) and 0xc (0x199d7c, 0x19ae6c).
- 0x197e70 returns 1 for the states 1–5 and 7. The static analysis does not show if 0x197e70 receives this object or an interface in it.

Other results:

- The task 0x284b0c is the keep-awake task. It grants a query when a client is active. No client excludes a different client. Thus the client 0x19 is not blocked by a USB client.
- The client 0x1c (0x287dd4) opens a file in the "Resources" folder. It is not a USB client.
- The DMA memory 0xad80c comes from the general allocator (0x25a974 and 0x28ce4c). The art caches use the same allocator.
- No art code (0x205db4, 0x20620c, 0x2059d0, 0x206b78, 0x206b98) has a literal for the USB host data (0x1083e0f8) or the EHCI registers (0xC5000000). The code literals for 0x1083e0f8 are at 0xb8cd8–0x1234dc and 0x2860e4–0x286200 only.

Result: the static analysis does not show which gate closes in host mode. Each gate depends on a state that changes at run time. To find the gate, read the state on the real iPod.

Probe 1.14 reads the gates 1–4 and the photo import state on the real iPod. It calls only 0x1bfb74, 0x19a51c and 0x197e70, and reads RAM; it adds no hook. Tag 62 has the art cache, tag 63 the library flag, the counts, the import state and the play queue. The records come before the host start (phase 0), after it (1), in host mode (2), after the audio test (4) and at each later log write (5).

## The art in host mode: probe 1.14 (2026-10-15)

The real iPod, "Start the Probe Without Music", a song with art, Now Playing. The art is missing. Each art record has the same values:

| Value | Result |
|---|---|
| The capacity + 0x74 | 0x100000 (the cache is open) |
| The library + 0x54 | 1 (open) |
| + 0x78 and + 0xc | 0: the art cache list has no track |
| The photo import state | 1 (0x197e70 returns 1), also before the host start |
| The play queue + 4 | 0 before the song, then not 0 |

Thus gate 3 is closed: no track reaches the art cache list. The photo import state is not the cause, because it is the same before the host start.

The path of a track request (Ghidra):

1. The player gets a new track: 0x87cec calls 0x1bfe84(library, track id).
2. 0x1bfe84 puts {track id, 1} into the library queue (+ 0x10, nodes at + 0x14). It makes the event 0x55000000 (0x1300f4) and posts it to the library (0x13d6d4).
3. The library handler 0x1c020c (vtable 0x66eda0, event type 0x10) calls 0x1c00e8 if the library is open.
4. 0x1c00e8 empties the library queue and calls 0x1bfe18 for each track.
5. 0x1bfe18 calls the method + 0x1c (0x206c5c) of each cache entry (library + 0x3c) with the byte + 8 set.
6. 0x206c5c puts {track id, 1} into the cache queue (+ 0x20, nodes at + 0x24).
7. The task: 0x206860 empties the cache queue. 0x205e64 finds the art formats of the track and adds them to the list (+ 0x78 increases).

Probe 1.15 counts the library queue, the cache queue and the cache entries (tag 64). A full library queue shows that the event 0x55000000 does not arrive. A full cache queue shows that the task does not run. Two empty queues show that 0x1bfe18 or 0x205e64 stops the track.

## The art in host mode: probe 1.15 (2026-10-15)

Tag 64 in each record: the library queue 0, the cache queue 0, one cache entry, its byte + 8 = 1. After the song starts, the art cache + 0x71 changes from 1 to 0, thus the task ran. Thus the request passes both queues, and 0x205e64 adds no art formats.

0x205e64 needs the art of the track from 0x18d010. 0x18d010 calls 0x9b0a0(database, ...), and 0x9b0a0 does the lookup only if database + 0xd2c is not 0. The database is the app + 0x1c (the app pointer at RAM 0x1081da18).

Database + 0xd2c is the ArtworkDB handle:

- 0xa1ff0 sets it. It opens `iPod_Control\Artwork` (0xa9190) and loads `ArtworkDB` (0xafd5c). Only the first database load 0xb4a64 calls 0xa1ff0.
- 0x91164 frees it and writes 0. Only 0xb4fe4 (the database reload) and 0xa1ff0 call 0x91164.

The reload path: the app event 0x63800003 → 0x1ed9f0 sets the app + 0x484 (if + 0x489 is set) → 0x1e9f9c calls 0x1e78e8 → 0x1ec2c8 → 0xb4fe4, when the USB device state (RAM 0x108711d4 + 0x218) is 1. 0x1e78e8 sets the app + 0x48a. The event 0x63800003 comes from the notification handler 0x1e0458 (case 8 → 0x18ae70). The sender of notification 8 is not found yet.

Hypothesis: in host mode the reload runs, and the ArtworkDB handle stays 0. Probe 1.16 logs the handle, the reload flags and the USB device state (tag 65).

Rockbox (the local `rockpod` tree) has no USB host stack for the PP5022 (`usb-drv-arc.c` is device mode only) and does not use the ArtworkDB. Thus it gives no direct help here.

## The art in host mode: probe 1.16 (2026-10-15)

Tag 65 in each record, before and after the host start: the ArtworkDB handle is 0x13df3670 (database + 0xd2c and + 0xd14). The app + 0x484 and + 0x48a stay 0; + 0x489 is 1. The USB device state is 0, and 1 while the song plays. Thus no database reload occurs, and the reload hypothesis is wrong.

The end of 0x1c00e8 calls the method + 0x28 (0x206474, the task event) of each enabled cache. Thus each track request wakes the task, and 0x205e64 runs for the track. 0x205e64 adds nothing if one of these steps fails:

1. 0x18d010 → 0x9b0a0 → 0x9a0f8: the ArtworkDB entry of the track. 0x9a0f8 needs the first word 0x6974696c (0xa137c). It searches the sorted index + 0x620 (made at the first use by 0xa92ec) or the list + 0xc.
2. 0x21bbb4: the count of images of the format (two formats from the table at 0x206200).
3. 0x21bd64, 0x20540c, 0x12ca58, 0x12cb50 and 0x12cac4 (0x9b1b4, 0x9b164): the image record.

Probe 1.17 tests step 1 for the first entry of the ArtworkDB (tag 66).

## The art in host mode: probe 1.17 (2026-10-15)

Tag 66 in each record, before and after the host start: the ArtworkDB object starts with 0x6974696c, has 5218 entries in the list + 0xc, and the index + 0x620 is 0x10a28278. 0x9a0f8 finds the first entry through the list and through the index. Thus the ArtworkDB and step 1 of 0x205e64 are correct in host mode.

Steps 2 and 3 of 0x205e64: the formats come from the table at 0x2aa7f4 (7 and 8); 0x1be9dc gives the format code; 0x21bbb4 counts the images of the code; 0x12cac4 → 0x9b1b4 makes the path of the ithmb file (0x9b190 → 0x9c2e8) and reads its name with 0xa47a4 (→ 0xa4a30).

Probe 1.18 calls 0x205e64 itself for ArtworkDB entries 0, 1 and 2 (before the host start, in host mode, later) and logs + 0x78 before and after (tag 67). The action "Record the Art State Without USB Host" (trigger '3') gives the same records without the host start.

## The art: the baseline without the host start (probe 1.18, 2026-10-15)

The action "Record the Art State Without USB Host" (trigger '3') runs the probe start without the host start. The owner: the Now Playing art is also missing. Tag 67: the test calls of 0x205e64 add the art formats of ArtworkDB entries 0, 1 and 2 (+ 0x78 0 → 1 → 2 → 3, + 0xc the same). After the song starts, + 0x78 stays 3: the playing song is not added. All other records are the same as in host mode.

Thus the host mode is not the cause. The cause is in the part of the probe that runs in each mode: the tones and sleeps in the UI task, the 32 KB log buffer (0x25a974), and the log writes.

Each log write called 0x1a0120 and then 0x19ff0c. 0x19ff0c is not a disk flush:

1. It locks the memory cache manager (+ 0x48) and sets + 0x44 = 1.
2. While the user count + 0x6c is not 0, it sends the event 10 to the users (0x19f9b0 → 0x1300f4, 0x13d6d4) and waits on + 0x58.

Apple calls it only before the sleep (0xb43dc) and in 0x1ed828. The only caller of 0x1ed828 is 0x1ee8d0, the sleep sequence (Ghidra, 27 October 2026). An earlier version of this note said "at the start of the disk mode"; that path is not known. At the end of the disk mode, 0x1ed918 calls 0x19ff6c, which sends the event 5. The probe never sent the event 5. Probe 1.13 not started wrote no log, and the art loaded.

Probe 1.19 does not call 0x19ff0c. The disk mode start writes the file data to the disk.

## The art: the root cause (probe 1.19, 2026-10-15)

Probe 1.19 does not call 0x19ff0c. Baseline without the host start: the owner sees the Now Playing art. Tag 62: + 0x78 is 3 after the three test calls, then 6 and 8 while songs play (in 1.18 it stayed 3). The only change from 1.18 is the removal of 0x19ff0c after each log write.

Root cause: 0x19ff0c (with 0x1a0120) after each log write of the probe. Apple calls it only before the sleep and before the disk mode. The probe called it many times and never called 0x19ff6c. After it, the request of the playing track did not reach the art cache list. The exact step that 0x19ff0c stops is not measured, because the fix removes the call.

Host mode with probe 1.19 ("Start the Probe Without Music"): the owner sees the art; + 0x78 grows from 3 to 7 and 10. Thus the root cause is confirmed in host mode. A connection to the Mac while host mode runs froze the iPod.

## The volume and the buttons (Ghidra, 2026-10-15)

The volume of the iPod:

- The app object (pointer at RAM 0x1081da18) keeps the volume level (0–100) at + 0x758. 0x1e9e88(app, level) sets it.
- 0x88ff8 calculates the output volume (level × maximum / 100, 0–256). 0x1eee50 writes it to + 0x40c at each change, then sends it to the audio system with the property 0x607c (0x1928f4).
- 0x1e8d10(app, step, show) is volume up. 0x1e9c84(app, step, show) is volume down. show = 1 opens the volume overlay (0x1eaacc). These methods change the UI state, thus they must run in the UI task.

The keys of the UI handler 0x1d8aa4 (called by 0x1d81cc for the key types 4–7):

| Key code | Action |
|---|---|
| 0x3a | Play/pause toggle |
| 0x3b, 0x3c | Play, pause (probable) |
| 0x3d | 0x1e75c0: a volume state (probably mute) |
| 0x3e, 0x3f | Next and previous track (0xa9830, 0xada3c) |
| 0x47, 0x48 | Fast forward and rewind: 0x1ec3c0 sets app + 0x6dc to 1 or 2, then a 500 ms timer; the release calls 0x1eefe8 |
| 0x49–0x4c | 0x1ac198 with 0x6e, 0x6f, 0x57, 0x58 |

No key for volume up or down is found yet.

The key events: 0x2141fc(0x14) gives a 20-byte event, 0x222d74 fills it (type, source, code), and 0x13d524 sends it. The key class (vtable at 0x2a9bb0) has the methods 0x13d148 (push, type 4), 0x13d4b8 (repeat, type 5), 0x13d4f8 (held, type 6) and 0x13ce10 (release, type 7). 0x13d524 calls the handlers at once, in the task that calls it (0x101800 gives the context of the current task). Thus a different task must not call it.

The EarPods: interface 3 (HID, report descriptor 31 bytes, endpoint 0x85) and interface 4 (HID, 42 bytes, endpoint 0x86).

Probe 1.21:

- It reads app + 0x40c in each wait of USBAudioTask and sends SET_CUR volume to the EarPods, without a wait (40 · log10(v / 256) dB, clamped to the UAC2 RANGE of the device; v = 0 gives 0x8000, silence).
- It reads the report descriptors, polls the interrupt endpoints with its own periodic queue heads (S-mask 0x04, C-mask 0x70, hub 0, port 1, each 8th frame), and logs each changed report.
- The buttons do not act yet: a safe path into the UI task is not found yet.

## The volume and the buttons: probe 1.21 result and the key path (2026-10-16)

Probe 1.21 on the real iPod: the EarPods volume follows the click wheel, with no gaps in the music.

- The volume range of the EarPods (UAC2 RANGE): −60 dB to 0 dB, resolution 0.5 dB, one sub-range.
- All 51 SET_CUR requests were correct (status 0). The iPod output went from 0 (silence) to 128 of 256 (−12 dB).
- Interface 3, report descriptor (31 bytes): `05 0C 09 01 A1 01 85 01 15 00 25 01 09 CD 09 E9 09 EA 09 CF 95 04 75 01 81 02 95 0C 81 05 C0`. Report ID 1; bit 0 play/pause (0xCD), bit 1 volume + (0xE9), bit 2 volume − (0xEA), bit 3 voice command (0xCF); 12 constant bits.
- Interface 4 (42 bytes): a vendor page (0xFF00) with report ID 1 (output, 63 bytes) and report ID 2 (input, 63 bytes). No buttons.
- The reports: `01 04` volume −, `01 01` play/pause, `01 00` release.

The key path into the UI task:

- 0x13d6d4(event, target, async, sender, 0) puts an event into the message queue of the task of the target when async = 1 (0x151c10 → 0x1517d4 → 0x120e7c). The target port is target + 0xc → + 0xc → + 0x1c. If sender = 0, it reads the context of the current task (0x101800, then + 0x1c); a task without a context would give a wrong value. Thus the probe gives the sender.
- 0x1d2ee8 and 0x1d32e0 post to the app target at RAM 0x1081da80 in this way. The player tasks call them.
- The key code is bits 16–23 of event + 0x10 (0x2564b0).
- The codes 0x7b and 0x7d are not compared by any key handler (0x14dd30 compares them as text characters only).

Probe 1.22: USBAudioTask posts key events. Play/pause uses Apple's key 0x3a (push and release; 0x1d8aa4 acts at the release). Volume + and − use the private codes 0x7b and 0x7d, with a repeat while held. The probe's `hook_event` (0x1d8260, UI task) catches the private codes and calls 0x1e8d10 or 0x1e9c84 with a step of 5 and the volume bar.

## The buttons: the key path of the remote (2026-10-16)

Probe 1.22 on the real iPod: the buttons did not operate the iPod. The log: each button report decoded correctly, and each post with 0x13d6d4 returned 1 (USBAudioTask has an app context; sender 0x135747f4, app port 0x13e5b094). But no record of the UI hook came. Thus a `MsgS` message to the app target does not reach the key handler 0x1d81cc.

The message table of the UI task (0x2a9bac, entries {kind, handler, 0}):

| Kind | Handler | Action |
|---|---|---|
| `kDwn` | 0x13d148 | A key push: makes the type 4 event and gives it to 0x13d524 in the UI task |
| `kAut` | 0x13d4b8 | A key repeat (type 5) |
| `kP&H` | 0x13d4f8 | A key held (type 6) |
| `kUp ` | 0x13ce10 | A key release (type 7) |
| `time` | 0x13cf8c | A timer |
| `MsgS` | 0x13d368 | An event to one target (0x13d6d4) |
| `Weel` | 0x13cfcc | The wheel |

0x1ac198(code, down, interrupt) sends `kDwn` or `kUp ` with the key code in bits 16–23 (0x151a40: with interrupt = 0 a locked queue and the event 0xd1e70; else a queue for an interrupt). It keeps the state of each key in tables at RAM 0x10883478 + code and 0x10883589 + code. The table at 0x10883510 has 0x79 entries, thus the codes are 0–0x78. The callers: the front buttons (0xada4c), the Simple Remote (0x1e6a84) and others.

The Simple Remote handler 0x1e6a84 (lingo class methods 0x1e6850 and 0x1e6950) maps each bit of the button mask to a key code with the table at 0x63ef30:

| Bit | Button | Key code |
|---|---|---|
| 0 | Play/pause | 0x1c |
| 1 | Volume up | 0x20 |
| 2 | Volume down | 0x1f |
| 3 | Next track | 0x1e |
| 4 | Previous track | 0x1d |
| 5–25 | Next album, previous album, stop (0x3a), play (0x3b), pause (0x3c), mute (0x3d), …, menu (0x49), select (0x4a), up (0x4b), down (0x4c) | 0x38–0x4c |

This corrects the note above: 0x3a is Stop, not Play/Pause.

Probe 1.23 calls 0x1ac198 with 0x1c, 0x20 and 0x1f at each push and release of an EarPods button (third argument 0). The UI task makes the repeats and the volume bar, as for an Apple Remote.

Real iPod, probe 1.23 (2026-10-16): **all EarPods buttons operate the iPod as expected** (volume +, volume −, play/pause). The log has 12 pushes and releases of volume − and 3 of volume + (then the log was full); 0 underruns.

## The freeze at a new connection in host mode (Ghidra, 2026-10-16)

The owner: in host mode, a disconnection and connection of the dock freezes the iPod (since probe 1.6), and a connection of the Mac also froze it (probe 1.19). The UI stays alive after the disconnection (1.11: the stop record came from a later log write); the freeze comes at the reconnection. Probe 0.1.61 survived a disconnection.

The USB device task (0x170f2c) runs at the same time as the host stack, on the same controller. Its loop:

1. It waits on its event until its state (+6) is 3 (USB power).
2. `bl 0x24d3c4` at 0x170fc8: 0x24d3c4 → 0x24cfac → 0x220e0c, the device start. It sets up the endpoints, sets a USBCMD bit (0x2204f8) and installs and enables the device interrupt handler 0xcd8e0 (0x18a870, 0x18a824).
3. `bl 0x24cd34` at 0x170fd8: the session.
4. `bl 0x24d49c` at 0x170fe0: the stop (0x24d0dc → 0x220f34).

After both `bl` sites the loop uses only r0 (`cmp r0,#0`) and r4.

The session 0x24cd34:

- It runs while OTGSC bit 11 (B-session valid) is set (0x220278, device + 0x3c).
- It tests and clears USBSTS bits (0x220b80 with 0x40, 0x100, 4 and 2; bit 2 is also the "port change" bit of the host).
- It ends when VBUS goes away, or when the abort flag at RAM 0x108318ec + 5 is set; then it clears the flag (0x24c5a4).

The device stop 0x220f34 removes the device interrupt object (0x18a888), stops the controller and sets the USBCMD reset bit. Then it waits without a limit until the reset ends.

The UIM "delete endpoint" (0x970a8, dispatch table 0x6c8820 + 0x50) finds the queue head with 0xffe6c (async) or 0xf3700 (periodic). The async unlink 0xe8c20 waits without a limit: for USBSTS bit 15 = 0 when the list becomes empty (after USBCMD bit 5 off), else for USBSTS bit 5 after the doorbell (USBCMD bit 6). The periodic unlink 0xe0074 has a limit of 150 tries.

`USBPowerSense` (0x2856a4) watches the VBUS GPIO (0x2218ac; the object vtable 0x66add4). Its change handler 0x1710d0 sends the notifications 4 and 5 (0xcd30c → 0x1173ac → 0xb0848 → 0x1e0458). Notification 4 gives the app events 0x6380000d and 0x6380000e (0x18ac94); the app handler 0x1ebb6c keeps the power state at app + 0x485 and pauses the music when the power goes away (0x1e9090).

The chain of the freeze:

1. The dock gives VBUS from the start, thus a device session runs when the probe starts host mode.
2. A disconnection removes VBUS. The session ends, and the device stop resets the controller under the host stack.
3. The UIM deletes the queue heads of the dock and waits forever in 0xe8c20.
4. A reconnection (the dock or the Mac) gives VBUS again. The device task starts the device mode on the same controller and takes the USB interrupt. The iPod freezes.

The probe's own control queue head in the asynchronous list does not break 0xe8c20: Apple's tail link takes its place.

Probe 1.24: `bl` hooks at 0x170fc8 (`hook_device_start`) and 0x170fe0 (`hook_device_stop`). While host mode runs (`host_running`), the start returns 1 ("failed", the task waits again) and the stop is skipped. Before the host start, `device_handover` sets the abort flag and waits at most 2.5 s for Apple's own stop of the session; if no session runs, it clears the flag again. Tag 74 records each step; a short high tone marks a blocked start.

## Probe 1.24 result and the reconnection (2026-10-16)

Real iPod, probe 1.24: **no freeze** when the dock was connected again, and no freeze when the Mac was connected. Tag 74: before the host start no device session ran (OTGSC 0x00080000, bit 11 off; the wait used the full 2.5 s, then the flag was cleared). At the disconnection the music route stopped (reason 1). At the reconnection the device task tried to start the device mode, and the probe blocked it (OTGSC 0x7f2e00, VBUS present). Then the root port showed the dock connected and enabled again; the log was then full.

After the reconnection the EarPods had no sound and no controls: the probe started the music route only one time. The music also paused at the disconnection: this is Apple's behaviour when the external power goes away (0x1ebb6c → 0x1e9090).

The EarPods send only one bit for the middle button (0xCD). The firmware has no logic for two or three pushes; the Simple Remote table has separate keys for the next track (0x1e) and the previous track (0x1d).

Probe 1.25:

- At each music stop: the probe takes its control queue head out of the asynchronous ring (`control_unlink`; the UIM builds a new ring when the dock goes away), clears `audio_found` (the next enumeration gives the new address) and resets the volume and button state.
- The first button press after the new enumeration starts the music route again in the UI task (`hook_event`).
- The middle button: one push is play/pause (0x1c), two pushes the next track (0x1e), three pushes the previous track (0x1d), after 400 ms without a new push.

## Probe 1.25 result and the stop at a disconnection (2026-10-16)

Real iPod, probe 1.25: **after the reconnection the headphones operate again** (sound, volume, buttons) after a button press. Two pushes (next track) and three pushes (previous track) of the middle button operate well. But at the disconnection the playback stopped completely, not only paused. The log was full before the disconnection (the button records).

Ghidra:

- The play state is 0x9ba00(database): 1 playing, 2 paused, else stopped. 0x1e798c and 0x1e7848 use it.
- Apple's power handler 0x1ebb6c calls 0x1e9090 only if the flag app + 0x486 was set at the power-on. 0x1e9090 is the action of the pause key 0x3c in 0x1d8aa4, thus a pause, not a stop.
- The probe stopped the route in the UIM task (in `hook_port_status`), at a time when USBAudioTask can hold 12 to 24 packets of the decoder. Then 0x1a2fa8 cleared the queue of the USB source under it. Apple's own stream stop 0x13221c makes the same calls, but in its own order: the stream off, the cancel of the endpoint (0x24bf7c), then the route (0x1a2fa0) and the flush (0x1a2fa8).

Probe 1.26: `hook_port_status` only sets `stop_request`; USBAudioTask stops the route at its next wait (between two sets). If the player played, the probe then sends the remote Pause key (0x3c) with 0x1ac198. Tag 75 records the play state before and after the stop, after the pause key and at the later log writes. The button, key and volume records are fewer (40, 40, 30), so that the log has space at the end.

## Probe 1.26 result, the volume at the start and "unsupported device" (2026-10-16)

Real iPod, probe 1.26: **the song pauses at the disconnection** (tag 75: playing before the stop, paused after the pause key and later). Two problems remain:

1. The headphones start too loud. The owner turned the volume down at once (iPod output 72 → 32 of 256). The curve 40·log10(v/256) gives −12 dB at half volume, much louder than the headphone jack of the iPod.
2. At the reconnection, the iPod shows "unsupported device", and that screen ends the playback.

Ghidra, the USB host message:

- 0xd9cec(type, error) sends the notification 0x12 (0xcd314) to the UI, which shows the USB host message. Callers: 0xd399c (in add device 0xd377c), 0x10c204, 0xe2be0 and 0xc0c38 (a conditional `bleq`).
- Add device 0xd377c: a hub (class 9) is accepted if USB_GLOBALS[0] > 1, or if the hub count USB_GLOBALS[1] < 3 and (USB_GLOBALS[0] ≠ 0 or the count is 0). Errors: 0x673 and 0x67d (hub not allowed), 0x68c (no driver).
- The dock has devices without a driver of the probe (the card slot, which has no storage driver since 1.11, and the billboard), thus each enumeration gives 0x68c. At the first start the music did not play yet.

Probe 1.27:

- `bl` hooks at 0xd399c, 0x10c204 and 0xe2be0: while host mode runs, `hook_usb_message` does not call 0xd9cec and logs the error (tag 74, event 6). The site 0xc0c38 is a `bleq`; a hook would make it unconditional, thus it stays.
- The volume curve is −48 · (1 − v/256) dB (half −24 dB, three quarters −12 dB, full 0 dB), clamped to the range of the device. The 1 kHz test tone also uses the iPod volume (before, the default volume of the device).

Real iPod, probe 1.27: all as expected. No "unsupported device" at a reconnection, the song pauses and continues after Play, and the volume levels are good.

## Stage 3: the USB mode manager and the patch usb-audio-out (Ghidra, 2026-10-16)

The task 0xb95a4 makes the USB mode manager (0x184aec) and keeps its pointer at RAM 0x1081edc4. It registers three clients (0x184ab8; the client method +8 gives its mode id):

| Client | Object | Mode id | Start (+0x18) | Stop (+0x24) |
|---|---|---|---|---|
| Idle | 0x24d7a4 | 0 | | |
| Device | 0x170fec, vtable 0x66ad9c | 1 | 0x170f24: 0x170ec0(obj, 3), state 3, wakes USBDeviceTask | 0x170f0c → 0x24d0a4: if VBUS, the abort flag 0x108318ec + 5 and a wake of the session |
| Host | 0x1422e8, vtable 0x668598 | 2 | 0x1422c0: Camera Connector "on" (0x1fb50c(1)), host start 0x2860e8, state 3 | 0x142298: host stop 0x28608c (0xb9358(1), a sleep of 2 s, 0xb963c, the UIM finalize, the pools free), Camera Connector "off", state 5 |

The vtable offsets are from the vtable base (two zero words, then +8 the mode id). The shared methods are +0x14 0x224ae4 and +0x28 0x224af4.

- The manager's mode is byte +0. Its lock is at + 0x10.
- `0x184860(manager, m)` (0x184a04) starts mode m, but only from mode 0: the stop of client 0 (+0x24, +0x28), then the start of client m (+0x14, +0x18).
- `0x18482c(manager, m)` (0x1849d4) stops mode m: the stop of client m, then the start of client 0. The mode is then 0.
- The loop of the task 0xb95a4:
  1. It waits for USB power (0xfdd38).
  2. If the mode is 2, it stops the host at 0xb9614 (`bleq 0x18482c`).
  3. It starts mode 1 (0xb9620).
  4. It waits while the power stays (0x10c06c), then stops mode 1 (0xb9630).
- The system notification handler 0x1e0084 starts and stops mode 2 for the Camera Connector (0x1e030c, 0x1e034c, 0x1e0370).
- USBDeviceTask (0x170fec) gets the object address as a decimal string (0x7b240 "%u"); its entry 0x170ea4 converts it (0x260608).
- The task creation is 0x11c808(name, entry, argument string, priority, stack size, a, b). The argument string is split at spaces into at most 10 words. USBDeviceTask uses priority 0x20 and the stack values 0x1000, 1, 3.

The patch `patches/usb-audio-out` (version 1.0) uses the manager:

- **On:** it stops mode 1 (Apple's end of the device session; it waits at most 2.5 s for the stop while VBUS is present), sets `host_running`, and starts mode 2. The host client starts the host stack. If the start fails, the patch calls 0x2860e8 itself.
- **Off:** USBAudioTask stops the route (the song pauses). Then the patch stops mode 2 (Apple's host stop) and, with USB power present, starts mode 1. Then a computer can see the iPod.
- A `bl` hook at 0xb9614 keeps the host mode at a new VBUS while USB-C Audio is On. The patcher makes the conditional call unconditional, thus the hook acts only for the call with the manager and mode 2.

## The main menu item of usb-audio-out 1.3 (2026-10-17)

The owner asked for USB-C Audio in the main menu, as Album Artists. Results (static, then the emulator for the UI):

| Fact | Evidence |
|---|---|
| The main menu (Menu 24094) has no On/Off row. Backlight (0x5f93), Shuffle Songs (0x5f9e) and Sleep (0x5f94) are action items: +0x04 = 0x20 (no arrow), +0x0c = their script. | Static |
| The On/Off rows of Settings (Menu 24598) have +0x08 = 0x3eb2, +0x0c = 0x4382 and the settings key at +0x1c. | Static |
| A copy of the Sound Check row in Menu 24094 shows its label, but no value, and the highlight does not stop on it. Thus it is not usable. | Emulator |
| A copy of Backlight with a new label is selectable. The `activate` hook (vtable slot 0x6776f8) sees its selection. | Emulator |
| 0x23ca4c (`activate`) only calls 0x239f7c(list, row, tag). 0x239f7c sets the selected row (vtable +0x15c, then list data + 0x14). With tag 0 it returns before the selection event (vtable +0x194). | Static |
| A call of 0x239f7c(list, row, 0) after the toggle draws the row again with the new text. Without it, the text changed only at the next redraw. | Emulator |
| The first instruction of 0x105a04 is `sub r0, r0, #0x5c00`. It does not use the PC, thus a `b` hook with `chain` can replace it. | Static |

The method of the patch is in [docs/modifications.md](../docs/modifications.md#usb-audio-out) ("Main menu item").

## The slower scrolling with USB-C Audio On (2026-10-17)

The owner: the menus, mostly the scrolling, are a little slower while USB-C Audio is On. Results (static, then the emulator):

| Fact | Evidence |
|---|---|
| The card reader of the dock gets no driver (the storage record is 0xff), thus no transfers. The interrupt endpoint of the dock's hub (interval 255) is polled by the controller, not by the CPU. | Code, earlier results |
| Apple's USB host task (entry 0xd3390, made at 0x119388 by the host start 0x2860e8, priority 0x10) loops: `0x2782f4(queue, buffer, 0x38, 1)` at 0xd33b0, then the poll 0xb9004 if no message came. | Static |
| 0x2782f4: the last argument is the wait in ticks. Not 0: 0xeb034 → 0xa0e44(semaphore, ticks) → 0xa697c. 0: 0xd1e78, a wait with no limit. | Static (machine code) |
| 0xb9004: method +0x64 of 16 slots (0xc7544), 0xf176c, 0xdda08, then method +0x70 of 16 slots (0xeccec). | Static |
| With On and no device, 0xb9004 ran each 1.02 ms (`IPODFW_MARK_AT=0xb9004`, emulated µs): about 1000 times each second, about 1500 instructions each time. The two slot loops were 17 % of all instructions. | Emulator |
| Busy instructions in 30 s: Off 298 M, On 364 M. | Emulator (`state`) |
| After Off, 99.6 % of the instructions are in 0x97230: the UIM stop writes USBCMD = 0 and waits with no limit for HCHalted (USBSTS bit 12). The emulator has no USB controller. | Emulator, Static |
| The UIM init (0x97300) sets USBINTR = 0x0b: the transfer interrupt, the error interrupt and the frame list rollover. No interrupt each 1 ms. | Static |
| 0x264d78(3) and 0x266464(1) in the UIM init set power-chip registers and the USB PHY clock (0x70000020 bit 31, then a wait for 0x70000028 bit 7). They do not change the CPU clock. | Static |
| USBAudioTask wakes once for each set of 12 packets: about 83 times each second. | Code |
| The probe 1.11 value "host mode 10 % of the CPU" is not valid for the patch: that probe also wrote a log and called 0x19ff0c. | Earlier results |

Version 1.4 of `usb-audio-out` (branch `usb-audio-speed`): a `bl` hook at 0xd33b0 gives 8 ticks while the route runs, and USBAudioTask makes two sets of packets in each wake. Emulator variant (the condition On): the poll each 8.17 ms, busy instructions with On 300 M in 30 s.

Real iPod, version 1.4: still stuttery. The owner's comparison on the same list: music through the headphone jack smooth; On, dock and EarPods, music paused: smooth; USB music at 48 kHz and at 44.1 kHz: stutters. Thus the cause is in the USB music path, not in host mode and not in the rate conversion.

Task priorities (the `bl 0x11c808` calls, `mov r3, #priority`): a higher number is a higher priority. Examples: ATAWorkLoopTask 0xc0, a task class at 0xc52fc 0x80 (name from a parameter), USBDeviceTask, ArtworkLoadTask, TimeManager 0x20, WindowManager, EventManager, eAppMotor, USBStatusTask, USBTaskTimeTask (the host task 0xd3390) 0x10, LoadDataTasks and the photo tasks 0. The kernel task switch is in 0x27f5f0 (the kernel request 0x84644); the patch does not hook it.

Version 1.5 is a measurement build: the task "USBMeasure" (priority 0x10) sleeps 10 ms and records how late it wakes; one record each second (tag 76).

Real iPod, version 1.5 (2026-10-17, 220 records). Mean values of the periods without scrolling:

| State | Core 0 idle | Core 1 idle | Latest wake of USBMeasure |
|---|---|---|---|
| Off, paused | 94 % | 100 % | 2–6 ms |
| On, host mode, no route (1 record) | 85 % | 100 % | 0.7 ms |
| On, USB route, paused (silence packets) | 78 % | 100 % | 4–8 ms |
| Off, playing through the jack | 58–60 % | 69 % | 49 ms (one each second) |
| On, playing through USB | 42–44 % | 69 % | 77–90 ms (one each second) |

- While the owner scrolled, core 0 was 2–15 % idle in all states, also with the jack, and USBMeasure woke 100–300 ms late. Thus the scrolling uses all free time of core 0, and the lateness of a 0x10 task during the scrolling is not a measure of the cause.
- The decoder load on core 1 (31 %) is the same for the jack and for USB.
- USB music uses about 15 % more of core 0 than jack music. The USB route uses about 16 % also with the music paused.
- USBAudioTask: 41–43 wakes each second, the longest packet fill (Apple's 12 packets, from the end of the wait to the send hook) 1.7–2.6 ms, also with the music paused; no sleep overshoot; at least 23 frames in front after each sleep (no underrun).
- 83 sets each second × about 1.9 ms is about 16 % of core 0. This agrees with the difference. Thus the probable cause of the stutter is the time of Apple's packet fill (0x1e3064 and its rate converter 0x1e2de0), not the number of wakes. Version 1.4 changed only the number of wakes. Open: confirm the mean fill time and find the cost inside 0x1e3064.

Ghidra (2026-10-17), the packet fill:

| Address | Function |
|---|---|
| 0x1e3064 | (source, bytes): a packet buffer from the pool (0xd3e70, 24 entries), then 0x1e2c90, or the test signal 0xdbdb4. |
| 0x1e2c90 | (queue, buffer, frames): takes the frames from the 6-entry queue (12 bytes each: pointer, count). An empty queue: 0x7cd28 clears the buffer (silence). An used entry goes back to the decoder (0xfed68). |
| 0x1e2de0 | If source + 0x7c is 0: a copy (0x7cae0). Else the rate converter 0x1e0bd8 (state at source + 0x50). |
| 0x1e2bdc | Gives a packet buffer back to the pool (a search of 24 entries). |
| 0x10fbb4 | The packet size: two divisions (0x82694). |
| 0x11c9fc | The sleep: the kernel delay 0xa62b4, then a yield loop (0xa69b4, request 0x1c) until the timer (0x28407c) shows the time. |

Thus at equal rates a set of 12 packets is about 2 KB of copies or clears. That is not 1.9 ms of CPU, and the music route costs about 16 % also with silence packets. The probable cost is outside the fill. Version 1.6 counts the USB interrupts (a wrapper in front of Apple's host handler 0xffd1c), the siTD errors and the messages of the host task each second (tag 77). The siTDs and the HID qTDs of the patch do not set IOC; the controller still interrupts at a transfer error (USBERRINT) or a short packet.

Real iPod, version 1.6 (2026-10-17): 1 USB interrupt each second (the frame list rollover), 0 siTD errors; the host task 90–120 timeouts and 0 messages each second (the 8-tick wait); **Apple's packet fill about 129 ms in each second**, with the music playing and paused (84 sets: about 1.5 ms for each set). Thus the interrupts are not the cause, and the fill is the cost after all, also when it only clears the buffers. From the code (0x1e3064, 0x1e2c90, 0xd3e70, 0x1e2f74, 0x10fbb4, 0x1e2bdc) a set should take about 0.1–0.5 ms. The cause of the difference is not known.

The machine code of 0x1e3064: silence (r3 = 1 for 0x1e2c90) if source + 0 is not 0 or 0x1e2f74 returns 0. 0x1e2c90 reads the queue at source + 0x10: entries of 12 bytes (+0 the frames, +4 the decoder buffer, +8 the count, 16 bits), the read index at + 0x4e, the write index at + 0x4c, 6 entries (0x82694 for the next index). Version 1.7 does these steps in the patch (`hook_fill`) with word loops, while the route runs and no conversion is necessary.

Real iPod, version 1.7 (2026-10-17): the sound was correct, but the log had no packet of the fast fill, and the fill stayed at about 130 ms each second. Thus `hook_fill` always called Apple's fill.

Ghidra: 0x1e2f60 (source, rate) sets the output rate (+0xc, +0x6c), copies the input rate (+4) to +0x68, sets 16 bits and 2 channels (+0x70/+0x74, +0x78/+0x7c), and the converter flag +0x8c = 1 if one of the pairs is not equal (unless the byte at DAT_001e09ec is 2). The setup uses the software floating point (0x2a8a44, 0x2a85c4, 0x2a9310). 0x1e2de0 reads the flag as (source + 0x10) + 0x7c and then calls the converter 0x1e0bd8 (0x1e09f0 or 0x1e08f0). The patch calls 0x1e2f60 when the route starts, before a song plays. Hypothesis: the input rate at +4 is then not 44100, the flag stays 1, and the converter runs on each packet, also on the silence buffers of the decoder while paused. Version 1.8 records +4, +0xc and +0x8c each second (tag 78), and uses the fast fill when +4 equals +0xc.

Real iPod, version 1.8 (2026-10-17): the sound was correct, the scrolling not better. Each record: input 44100 Hz, output 48000 Hz, converter flag 1, Apple's fill about 122 ms in each second, also while paused. The cause of the flag: the option Sample Rate was still 48 kHz (from the 48 kHz test). The conversion 44.1 → 48 kHz is thus necessary, and Apple's converter (0x1e0bd8, software floating point in its setup) costs about 12 % of core 0. The hypothesis "the input rate is not 44100 at the route start" is wrong. Next: the same test with 44.1 kHz (then the fast fill runs).

Real iPod, version 1.8 at 44.1 kHz (2026-10-17): input and output 44100 Hz, converter flag 0; the fast fill made all packets (about 1008 each second), Apple's fill 0 ms; the fill 28–30 ms in each second (about 3 % of core 0, against about 130 ms before); core 0 idle without scrolling 51–55 % (USB 1.3–1.8: 42–44 %, the jack: 58–60 %); 0 siTD errors, at least 23 frames in front. The owner: the sound correct, the scrolling better. Thus Apple's packet fill was about 10 % of core 0 at 44.1 kHz, and Apple's converter (the option 48 kHz) is about 12 % of core 0.

## Open items

1. The UIM interrupt handler that completes the periodic transfers (Stage 2).
2. The sign for a new device: confirm that 0xe7a50 runs when a device connects (needs the real iPod; the emulator has no USB).
3. How to stop the device session when USB Audio Out is On (0x2856a4, 0x163ffc).
4. Does the UIM init enable port power (PORTSC bit 12)? The port power is not important if VBUS comes from outside.
