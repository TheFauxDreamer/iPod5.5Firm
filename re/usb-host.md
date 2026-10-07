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

## Open items

1. The UIM interrupt handler that completes the periodic transfers (Stage 2).
2. The sign for a new device: confirm that 0xe7a50 runs when a device connects (needs the real iPod; the emulator has no USB).
3. How to stop the device session when USB Audio Out is On (0x2856a4, 0x163ffc).
4. Does the UIM init enable port power (PORTSC bit 12)? The port power is not important if VBUS comes from outside.
