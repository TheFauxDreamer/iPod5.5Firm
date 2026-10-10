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

## Open items

1. The UIM interrupt handler that completes the periodic transfers (Stage 2).
2. The sign for a new device: confirm that 0xe7a50 runs when a device connects (needs the real iPod; the emulator has no USB).
3. How to stop the device session when USB Audio Out is On (0x2856a4, 0x163ffc).
4. Does the UIM init enable port power (PORTSC bit 12)? The port power is not important if VBUS comes from outside.
