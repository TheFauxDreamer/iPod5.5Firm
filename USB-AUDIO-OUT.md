# USB-C audio out: plan and status

This document is the plan for USB-C audio out on the iPod 5.5G. With this function, the iPod plays to USB-C headphones and USB DACs through a USB-C mod. Update this document after each stage with the results and the gate decisions.

| Item | Value |
|---|---|
| Status | Stage 1 is done. The probe patch for Stage 0 is ready on the branch `usb-audio-out` and tested in the emulator. Waiting for the hardware test of the owner. |
| Firmware | Apple RetailOS 1.3 (`iPod_25.1.3.ipsw`) |
| Patch | `patches/usb-host-probe` (letter `h`, Stage 0 test). Later `patches/usb-audio-out` (letter `u`). |
| Branch for the code | `usb-audio-out` |
| Research notes | [re/usb-host.md](re/usb-host.md) (host direction), [re/usb-audio.md](re/usb-audio.md) (source direction) |

## The goal and the direction

USB-C headphones and USB DACs are USB devices. Thus the iPod must be the USB host, and it must send audio to them (isochronous OUT transfers).

The firmware also has the opposite direction: a USB audio source, in which the iPod is a USB device. An MFi DAC that is itself the USB host (for example the OPPO HA-2SE) uses that direction. [re/usb-audio.md](re/usb-audio.md) records it. This plan is only for the host direction.

## Research results (Ghidra, 2026-10-06)

The firmware has a USB host stack from the Mac OS 9 USB family. Apple used it for the iPod Camera Connector. All offsets are osos image offsets.

| Part | Location | Notes |
|---|---|---|
| RW data copy | Table at 0x8406c: image 0x67e2a8 → RAM 0x10800004, size 0x4b7a8 | RAM address = image offset + 0x10181d5c. To change RW data, patch it at its image offset. |
| Class driver list | 0x6bc3dc (RAM 0x1083e138): pairs (driver record, dispatch table) | Hub (class 9), SampleStorageDriver (class 8), ICAType4CameraDriver (vendor 0x04A9), PTPCameraDriver (class 6, subclass 1, protocol 1). The records have the tag "usbd" (the Mac OS 9 `USBDriverDescription`). The dispatch tables have version 0x1100. |
| Host controller driver (UIM) dispatch table | 0x6c8820, version 6 | Init 0x97300, finalize 0x97228. Control 0x96f64/0x96ffc. Bulk 0x96d38/0x96db0. Interrupt 0x974ec/0x9762c. **Isochronous at 0x6c885c/0x6c8860 = 0xd4820/0xd4828: stubs (`mvn r0,#0; bx lr`, return -1).** Root hub 0x96c44, 0x970a8, 0x96e4c. |
| EHCI structures | QH 0xead78. qTD 0x9762c (token 0x8c80). Periodic frame list of 0x400, 0x200 or 0x100 entries (0x97300). | The ARC controller of the PP5022 in EHCI host mode. |
| Root hub simulation | GET_DESCRIPTOR 0x11117c. Requests 0xd26b0. Ports 0x967cc–0x96b48. | "USB 2.0 EHCI Root Hub Simulation" |

These are the results:

1. **The host driver has no isochronous support.** Every USB audio device needs isochronous transfers. The patch must add iTD (high speed) and siTD (full speed).
2. **No USB audio class driver exists for the host.** The patch must add one to the class driver list.
3. The PCM comes from the playback path: the ring 0x1e3064 and the sample-rate converter 0x1e2f60, which the USB source uses.
4. **The hardware is a risk.** The USB-C mod is wired as a device. Headphones need 5 V (VBUS) from the host and the host role on the CC pins. Possibly an OTG adapter with external power is necessary. The Camera Connector port was a low-power port.

**Feasibility:** the function is possible, but it is a large project. The emulator has no USB, thus each USB test must be done on the real iPod. Each stage has a gate, so the project can stop early.

## Rules

### Branches

- Stage 0 and Stage 1 (research notes, no code) go on main.
- Stages 2–4 (code) go on the branch `usb-audio-out`.
- Merge into main when a USB-C dongle plays on the real iPod and the normal USB functions pass the tests below.
- If a gate stops the project, delete the branch.

### The normal USB functions stay

- **USB Audio Out = Off (the default):** the USB-C port works exactly as now: charging, sync, disk mode and flashing. The patch never enters host mode. The new code is only on the host side (the isochronous UIM entries and the audio class driver). The device side never calls it.
- **USB Audio Out = On:** a computer or a charger supplies VBUS, and then the port works as usual. The patch tries host mode only when no external VBUS is present, or when no host answers. Stage 1 confirms the rule for the USB-C mod.
- **Limit:** the iPod has one port. While headphones are connected, the iPod cannot charge from that port.
- **Recovery:** set USB Audio Out to Off in Settings. The boot-flash disk mode (hold Select+Play at start) does not use osos, so a restore always works.

## Stage 0: hardware test with a probe patch

Stage 1 showed that the stock firmware enters host mode only after an iAP exchange with a Camera Connector (lingo 6). The USB-C mod has no iAP accessory, thus a test with the stock firmware cannot show a result. The test needs a small probe patch (on the branch `usb-audio-out`):

1. A menu item starts the host stack (0x2860e8).
2. The piezo clicks when the hub driver adds a device (hubAddDeviceHandler 0xe7a50).
3. Connect a USB flash drive or a card reader through a USB-C OTG adapter with a power input.
4. Record the result: a click, or no click.

Gate: a click proves that host mode works on the USB-C mod. No click: examine VBUS and the device session (re/usb-host.md, open items).

## Stage 1: how the firmware enters host mode (Ghidra, read-only)

Follow [docs/ghidra-guide.md](docs/ghidra-guide.md) §5, the procedure for an AI agent. Use the scripts in [re/ghidra-scripts/](re/ghidra-scripts/) and [re/find-pattern.py](re/find-pattern.py).

1. Find the callers of the UIM init 0x97300. Find the code that sets the ARC `USBMODE` to host and sets `OTGSC`/VBUS. Find the trigger: the accessory ID resistor, iAP from the Camera Connector, or the OTG ID pin.
2. Find the photo import screen and how it starts the host stack. Find the `USBPowerSense` task and how it senses external VBUS.
3. Find the UIM interrupt handler that completes the periodic transfers.
4. Record the results in [re/usb-host.md](re/usb-host.md) and in [docs/firmware-functions.md](docs/firmware-functions.md) (guide §5.4 and §8).

Gate: report to the owner. Decide if a patch can force host mode on the USB-C port with a setting.

## Stage 2: isochronous support in the UIM

The patch is `patches/usb-audio-out`, with the version letter `u`.

- **Space:** only 124 bytes are free in the normal patch area ([docs/patch-system.md](docs/patch-system.md)). Thus the code goes after 0x736800, below 0x7F0000. Extend the build so that a patch can use this area. The build moves rsrc (`FirmwarePartition.makeRoom`) and puts the patch after the Dark Mode items, with the method of `DarkMode.build` (`patchAt`, `maxSize: ThemeImport.ososLimit`). Make the same change in `src/ipodfw/patcher.py`.
- Replace the two stub entries with `"word"` hooks: 0x6c885c (`expect` 0x000d4820) and 0x6c8860 (`expect` 0x000d4828).
- Do full speed first (siTD, through the built-in transaction translator of the ARC). Then do high speed (iTD).
- Link the new descriptors into the periodic frame list of 0x97300. Complete them in the interrupt handler from Stage 1.

## Stage 3: USB Audio Class 1 host driver

- Add a driver record and a dispatch table, in the format of the records at 0x6c86e8 and 0x6c8780, for interface class 1, subclass 2.
- Add the driver to the driver list at 0x6bc3dc, with a `"word"` hook on the end of the list or a pointer to a longer copy.
- The driver does these steps:
  1. It reads the configuration descriptor.
  2. It selects the alternate setting for 16-bit stereo PCM.
  3. It sends SET_CUR for the sampling frequency: 44.1 kHz, else 48 kHz.
  4. It opens the isochronous OUT pipe (Stage 2).
  5. It sends 44 or 45 frames (or 48 frames) each 1 ms.
- Do UAC1 first. Do UAC2 (high speed, clock source) only after UAC1 works.

## Stage 4: audio path and user interface

- Take the PCM from the playback path (0x1e3064, 0x1e2f60). Mute the internal DAC while USB audio plays.
- Add a Settings item "USB Audio Out" On/Off with the Dark Mode menu method.
- The `dark-mode` patch already uses the settings get/set word hooks (0x66c94c, 0x66c950). Thus add a hook kind `"chain"` to the patcher (Swift and Python). It accepts the Apple value or a value from another patch, and it gives the old target to the patch as `<to>_next`. Change the two dark-mode hooks to `"chain"`.
- Make the Settings menu builder in `DarkMode.swift` accept more than one item.
- Add the patch switch and a help text in the Patches pane.
- Update the documents that [docs/README.md](docs/README.md) names for a new patch.

## Tests

- Patcher tests (`tests/test_patcher.py`, `mac/Tests/IPodFWKitTests/IPodFWKitTests.swift`): the UIM table words, the driver list, the `"chain"` hook (alone and after dark-mode), the extended area, and the Settings menu with two items.
- Run `uv run pytest` and `cd mac && swift test` with `IPODFW_IPSW`.
- Emulator: with the setting Off and with the setting On, the firmware starts and the menus work as before. The emulator has no USB.
- Real iPod: test the Stage 0 device, then a UAC1 full-speed USB-C dongle, then a USB DAC.
- Normal USB functions, with the setting Off and On: connect the Mac. The disk must mount, iPodFirm must flash, and the iPod must charge.
- Recovery: Select+Play disk mode must work.
- Build with `mac/scripts/build-app.sh`. The script increases the version and the build number.

## Results and gate decisions

| Date | Stage | Result | Decision |
|---|---|---|---|
| 2026-10-06 | Research | The host stack exists. The isochronous UIM entries are stubs. No audio class driver for the host. | Continue with Stage 0 and Stage 1. |
| 2026-10-06 | Stage 1 | Host start 0x2860e8 found. `USBMODE` = 3 in 0xd1288. The stock firmware enters host mode only after iAP lingo 6 with a Camera Connector, which probably supplies the 5 V. The patch can call the host start itself. VBUS must come from an OTG adapter with power. See [re/usb-host.md](re/usb-host.md). | Stage 0 changes: it needs a probe patch. Owner to decide. |
| 2026-10-06 | Stage 0 | The probe patch `usb-host-probe` (0x7e8000, extended area 0x7E8000–0x7F0000) is ready. Emulator: the trigger starts the host stack one time, and the menus continue to work. | Owner: flash it and do the hardware test. |
