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

## Open items

1. The UIM interrupt handler that completes the periodic transfers (Stage 2).
2. The sign for a new device: confirm that 0xe7a50 runs when a device connects (needs the real iPod; the emulator has no USB).
3. How to stop the device session when USB Audio Out is On (0x2856a4, 0x163ffc).
4. Does the UIM init enable port power (PORTSC bit 12)? The port power is not important if VBUS comes from outside.
