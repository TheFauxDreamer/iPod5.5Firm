# USB-C audio out: plan and status

This document is the plan for USB-C audio out on the iPod 5.5G. With this function, the iPod plays to USB-C headphones and USB DACs through a USB-C mod. Update this document after each stage with the results and the gate decisions.

| Item | Value |
|---|---|
| Status | **Complete (17 October 2026).** The patch `usb-audio-out` 1.0 plays the music through USB-C headphones and passed all test steps on the real iPod. |
| Firmware | Apple RetailOS 1.3 (`iPod_25.1.3.ipsw`) |
| Patch | `patches/usb-audio-out` (letter `u`). The research probe is `patches/usb-host-probe` (letter `h`). |
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
- If a gate stops the project, do not delete the branch. Keep the branch and all its documentation for future work.
- Record the stop reason in patches/usb-host-probe/FINDINGS.md and in this document.

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

- **Space:** only 124 bytes are free in the normal patch area ([docs/patch-system.md](docs/patch-system.md)). Thus the patch uses `"load_address": "extended"`: the build puts it after all other data (a theme, the Dark Mode items), below 0x7F0000, and moves rsrc. The patchers support this since 7 October 2026.
- Replace the two stub entries with `"word"` hooks: 0x6c885c (`expect` 0x000d4820) and 0x6c8860 (`expect` 0x000d4828).
- Do full speed first (siTD, through the built-in transaction translator of the ARC). Then do high speed (iTD).
- Link the new descriptors into the periodic frame list of 0x97300. Complete them in the interrupt handler from Stage 1.

**First test (2026-10-09):** the probe `usb-host-probe` (version 1.2) has a Stage 2 test without the UIM. It makes its own siTDs in the frame list and sends a 1 kHz tone to the EarPods for 5 s. The `"word"` hooks on the stub entries come later, with the driver of Stage 3. Details: [docs/modifications.md](docs/modifications.md#usb-host-probe), item 16.

## Stage 3: the patch usb-audio-out

The probe showed that the patch does not need a class driver or the UIM isochronous entries: it finds the device in the configuration that the composite driver reads, sends its own control requests and makes its own siTDs. The old plan (a UAC1 class driver in the driver list, `"word"` hooks on 0x6c885c and 0x6c8860) is not used.

The patch `patches/usb-audio-out` (letter `u`, version 1.0) is the code of probe 1.27 without the test parts, with:

- the Settings item "USB-C Audio" (On/Off, Off after each start);
- the task "USBAudioOut", which starts and stops host mode through Apple's USB mode manager (RAM 0x1081edc4) and starts the music route automatically when the headphones are enumerated;
- Off at once: Apple's host stop, then the device mode again.

Details: [docs/modifications.md](docs/modifications.md#usb-audio-out) and [re/usb-host.md](re/usb-host.md).

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
| 2026-10-06 | Stage 0 | The probe patch `usb-host-probe` (first at the fixed address 0x7e8000) is ready. Emulator: the trigger starts the host stack one time, and the menus continue to work. | Owner: flash it and do the hardware test. |
| 2026-10-07 | Stage 0 | The flash failed with "The code area of usb-host-probe is not empty": with "Switch on iPod" and the "Dark Gray" theme, the dark-mode code was at the fixed address. The probe is now an extended patch: the build puts it after all other data. Test with the owner's theme: correct. | Owner: flash again and do the hardware test. |
| 2026-10-07 | Stage 0 | The probe plays each sign one time, then a countdown of three beeps and 2 s of silence, then the real result. Emulator: correct timing. The real hub sign also comes in the emulator (the root hub is simulated in software). | Owner: flash and do the hardware test. |
| 2026-10-07 | Stage 0 | Real iPod: the host mode sign came. The photo import screen showed "unsupported device" with the 3-in-1 adapter and a card reader, with and without a card. No hub or storage sign. The probe now logs each class driver call (Show USB Log). | Owner: repeat the test, then send the log. |
| 2026-10-07 | Stage 0 | Real iPod: no log, because the photo import screen takes the button events. The probe now writes the log 10 s after the host start, flushes the disk cache and gives two short low beeps. Emulator: correct. | Owner: repeat the test. |
| 2026-10-07 | Stage 0 | Real log with the dock: only the simulated root hub. The probe now also logs the root port status and the controller registers (connection, speed, power, VBUS). | Owner: repeat the test with the dock, the 3-in-1 adapter and the Apple headphone adapter. |
| 2026-10-07 | Stage 0 | Real log with the dock: VBUS valid, the device connected, reset correct, **high speed**, control transfers running, but no driver call. The probe now forces full speed (the firmware's own PFSC path) and has a Copy Log button. | Owner: repeat the test with the dock. |
| 2026-10-07 | Stage 0 | Real log at full speed: connection, reset and port enable correct, but no driver call. Speed is not the cause. The probe now logs the control transfers (with the setup packets) and the transfer queue. | Owner: repeat the test with the dock. |
| 2026-10-07 | Stage 0 | Version 0.1.62 stopped on the real iPod after the first tone: probably a memory fault at a read in the 0x90000000 window, which the emulator allows. The probe now reads through 0x10000000. The owner's exact build works in the emulator. | Owner: repeat the test. |
| 2026-10-07 | Stage 0 | Real log: the dock answered the first GET_DESCRIPTOR (the qTD completed without an error), but the host stack never sent the next request. Probable cause: the USB interrupt goes to the device driver handler. The probe now removes the device handler before it installs the host handler. | Owner: repeat the test with the dock. |
| 2026-10-07 | Stage 0 | **The interrupt fix works.** The dock answered GET_DESCRIPTOR, got the address 101, and sent its full device descriptor (USB 2.1 hub). Then the stack stopped before the driver selection. The probe now logs each transfer completion. | Owner: repeat the test with the dock. |
| 2026-10-07 | Stage 0 | Same dock sequence; the completion records were all used by the root hub poll. The probe now logs only the completions of the device transfers. | Owner: repeat the test with the dock. |
| 2026-10-07 | Stage 0 | The dock's descriptor arrived correctly; the firmware then refuses external hubs by design (0xd377c, g[0] = 0). The probe now allows hubs and logs the driver selection. Findings: [patches/usb-host-probe/FINDINGS.md](patches/usb-host-probe/FINDINGS.md). | Owner: repeat the test with the dock. |
| 2026-10-07 | Stage 0 | With hubs allowed, the dock's hub (VIA Labs VL817) was accepted and configured by the hub driver. The log then reached its limits. The probe now has a 32 KB log and logs the interrupt transfers. | Owner: repeat the test with the dock. |
| 2026-10-08 | Stage 0 | The hub driver configured the dock's hub and powered its five ports, then started the status-change interrupt transfer. No port change came. The probe now logs the interrupt completions. | Owner: repeat the test with the dock. |
| 2026-10-08 | Stage 0 | No completion of the dock's status-change transfer and of its PORT_POWER requests. The probe now logs all queue heads with their state. | Owner: repeat the test with the dock. |
| 2026-10-08 | Stage 0 | Tests A and B: the status stage of the first PORT_POWER request to the dock's hub stays active; the time of the connection does not matter. The probe now dumps Apple's periodic table and switches the periodic schedule off for 2 s as an experiment. | Owner: test 0.1.71 with the dock. |
| 2026-10-08 | Stage 0 | **Firmware bug found** in the periodic insert 0xf5c80: the frame list pointed to a block of zeros, thus the dock's status-change endpoint was never polled. The probe fixes it (r1 = r0). The PORT_POWER status stage stall remains open. | Owner: test 0.1.72 with the dock. |
| 2026-10-08 | Stage 0 | **With the periodic fix, the dock's hub reported its ports and two storage devices behind it reached the storage driver (class 08/06/50).** The complete chain works. Fixes in the probe: host start without iAP, the USB interrupt handler, full speed, hubs allowed, the periodic insert. | Next: test the Apple USB-C headphone adapter through the dock. |
| 2026-10-08 | Stage 0 | **The USB-C EarPods (05AC:110B) enumerated through the dock** at full speed: device class 0xEF (interface association). "Add device" found no driver. The configuration descriptor was not read. | Next: the probe gives class 0xEF to the composite driver and logs the configuration descriptor. |
| 2026-10-08 | Stage 0 | The probe now gives class EF/02 to the composite driver (Ghidra: driver score 0xc50ac) and logs the configuration descriptor (decoded in Show USB Log). Emulator: correct. iPodFirm 0.1.79. | Owner: repeat the EarPods test through the dock. |
| 2026-10-08 | Stage 0 | **The EarPods are a USB Audio Class 2 device at full speed.** Playback: interface 1, alternate 2 = 16-bit stereo, endpoint 0x02 isochronous OUT, synchronous (no feedback), 192 bytes each 1 ms at 48 kHz. Two HID interfaces (buttons). Details: [FINDINGS.md](patches/usb-host-probe/FINDINGS.md#the-usb-c-earpods-05ac110b). | Stage 2 (isochronous transfers) and Stage 3 (a UAC2 driver) have the data that they need. Owner to decide. |
| 2026-10-09 | Stage 2 | The probe 1.2 sends a 1 kHz tone with its own siTDs (Ghidra: 0xad80c memory, the CPU and the controller use the same address). Offline: the device finder is correct for the EarPods log. Emulator: correct (no USB device). | Owner: test with the EarPods through the dock. |
| 2026-10-09 | Stage 2 | Probe 1.2 on the real iPod: no tone. The test did not start: the log was full, and the device finder read old cache data. Probe 1.3 reads the USB buffers directly (not through the cache) and keeps log space for the test. | Owner: test probe 1.3. |
| 2026-10-10 | Stage 2 | **The first USB audio from the iPod.** Probe 1.3 played a 1 kHz tone in the USB-C EarPods through the dock: SET_INTERFACE and SET_CUR 48 kHz correct, 5105 frames, 0 errors. | Stage 2 works. Next: Stage 3 and 4 (a driver in the firmware, the music as the source, the Settings item). |
| 2026-10-10 | Stage 4 | Probe 1.4: the music of the iPod to the EarPods through Apple's USB audio source (the Wadia path): the decoder buffers go to USBAudioTask, and hooks on its send and wait calls put the packets into the siTDs. 44.1 kHz, 12 dB lower. Emulator: the route and the hooks operate (no audio in the emulator). | Owner: test probe 1.4 with a song. |
| 2026-10-10 | Stage 4 | Probe 1.4 real: the stream ran (0 underruns) but with silence; the song stayed at 0:00. Cause: the iAP "Digital Audio" ready flag 0x1081dff6. Probe 1.5 sets it; emulator: the decoder buffers now go through the queue. | Owner: test probe 1.5 with a song. |
| 2026-10-10 | Stage 4 | **The music of the iPod plays through the USB-C EarPods** (probe 1.5). The UI is very slow, and the album art in Now Playing does not load. Probe 1.6 changes the wait of USBAudioTask to one sleep each cycle. | Owner: test probe 1.6 (UI speed). |
| 2026-10-10 | Stage 4 | Probe 1.6: the UI was still slow, no album art, most packets silence, and a reconnection of the dock froze the iPod. Probe 1.7 waits on the USB interrupt (as Apple's device code) and stops the music when the dock is disconnected. | Owner: test probe 1.7. |
| 2026-10-10 | Stage 4 | Probe 1.7 restarted the iPod after the tone (an event signal in the interrupt). Probe 1.8 posts the signal to a task with 0xadbdc. The music of 1.6 sounded correct. | Owner: test probe 1.8. |
| 2026-10-10 | Stage 4 | Probe 1.8 also restarted the iPod (the interrupt path). The emulator profile shows that the sleep blocks and that the copy of the probe was the largest cost. Probe 1.9: the sleep, a 32-bit copy, the volume on the EarPods, a CPU record. | Owner: test probe 1.9. |
| 2026-10-13 | Stage 4 | Probe 1.9: no restart, the music plays, the CPU of the music path is about 4 %, but the UI still lags, and a reconnection of the dock still freezes the iPod. Probe 1.10 logs the idle time of the CPU in each phase. | Owner: test probe 1.10. |
| 2026-10-14 | Stage 4 | Probe 1.10: scrolling correct; the UI stutters only where the Now Playing art must show, and the art is missing. Probe 1.11 gives no driver to storage devices (the card slot of the dock), so that the iPod does not enter the photo import state. | Owner: test probe 1.11. |
| 2026-10-15 | Stage 4 | Probe 1.11: the art still does not load. The idle statistics: host mode about 10 %, the music route about 30 % more. Ghidra: ArtworkLoadTask 0x205db4 and its steps. Probe 1.12 traces the task and has a mode without the music route. | Owner: two runs with probe 1.12. |
| 2026-10-15 | Stage 4 | Probe 1.12: the trace shows an empty request queue of ArtworkLoadTask. The owner: the art is missing whenever the probe is installed, also not started; the margin is not the cause. Probe 1.13 removes the 1.12 hooks. | Owner: test 1.13 installed but not started. |
| 2026-10-15 | Stage 4 | Probe 1.13 not started: the Now Playing art loads. The 1.12 trace hooks were the cause of that case. | Owner: the art with the probe started (without and with the music route). |
| 2026-10-15 | Stage 4 | Probe 1.13 started without the music route: the art is missing. Ghidra finds eight gates of the art load, but static analysis cannot show which gate closes. Probe 1.14 reads the gates and logs them (no new hooks). | Owner: "Start the Probe Without Music" with probe 1.14, then Now Playing. |
| 2026-10-15 | Stage 4 | Probe 1.14: the art cache stays open (1 MB), but its list of tracks is empty, also while a song plays. Ghidra: a track request goes from the player (0x87cec) through a library queue and the UI event 0x55000000 into the cache queue. Probe 1.15 counts each queue. | Owner: the same test with probe 1.15. |
| 2026-10-15 | Stage 4 | Probe 1.15: both request queues are empty and the task runs, thus the art lookup finds no art. Ghidra: the lookup needs the ArtworkDB handle (database + 0xd2c); the database reload 0xb4fe4 clears it and does not open the ArtworkDB again. Probe 1.16 logs the handle and the reload flags. | Owner: the same test with probe 1.16. |
| 2026-10-15 | Stage 4 | Probe 1.16: the ArtworkDB handle stays set and no database reload occurs, thus the reload hypothesis is wrong. The library handler wakes the task after each request, thus the lookup in 0x205e64 fails. Probe 1.17 tests the ArtworkDB object and the lookup 0x9a0f8. | Owner: the same test with probe 1.17. |
| 2026-10-15 | Stage 4 | Probe 1.17: the ArtworkDB and its lookup are correct in host mode. Probe 1.18 calls the art add step 0x205e64 for known ArtworkDB entries, and has a baseline action without the host start. | Owner: probe 1.18, the baseline, then host mode. |
| 2026-10-15 | Stage 4 | Probe 1.18 baseline without the host start: the art is also missing. The add step works for test tracks, but the playing song is not added. Thus the cause is not the host mode. Each log write of the probe called 0x19ff0c, which Apple uses only before the sleep and the disk mode. Probe 1.19 does not call it. | Owner: probe 1.19, the baseline, then host mode. |
| 2026-10-15 | Stage 4 | **Root cause of the missing art found.** Probe 1.19 baseline: the art loads, and the art cache gets the playing tracks (+ 0x78 3 → 6 → 8). The calls of 0x19ff0c after each log write were the cause. The UI is still a little slow. | Owner: probe 1.19 in host mode. |
| 2026-10-15 | Stage 4 | Probe 1.19 in host mode: **the Now Playing art loads** (+ 0x78 3 → 7 → 10). A connection to the Mac while host mode runs froze the iPod (the same problem as the dock reconnection). | Owner: the music route with probe 1.19. Later: the freeze at a new connection, the UI lag. |
| 2026-10-15 | Stage 4 | Probe 1.20 with the music route: **the music plays through the USB-C EarPods and the Now Playing art loads.** 80 436 packets, 0 underruns. Idle of core 0 during the music: 26–44 %; in the 1.19 baseline (no host mode, music on the headphone jack): 18–38 %. | Next: the freeze at a new connection in host mode, the volume, the UI lag, then Stage 3 (the real patch with a Settings item). |
| 2026-10-15 | Stage 4 | Probe 1.21: the iPod volume sets the volume of the EarPods (SET_CUR from app + 0x40c, without a wait). The probe reads the HID report descriptors of the EarPods, polls their interrupt endpoints and logs each button report. The art records are removed. | Owner: test probe 1.21 (the click wheel volume, the buttons). Then probe 1.22: the buttons as iPod controls. |
| 2026-10-16 | Stage 4 | Probe 1.21: **the EarPods volume follows the click wheel**, no gaps. The button reports decode correctly (report ID 1: play/pause, volume +, volume −). Probe 1.22 posts the buttons as key events to the UI task: play/pause (0x3a) and volume ± with the volume bar. | Owner: test probe 1.22. |
| 2026-10-16 | Stage 4 | Probe 1.22: the buttons did not operate the iPod; the key events posted to the app did not reach the key handler. Ghidra: the key path of the Apple Remote is 0x1ac198 with the remote key codes (volume up 0x20, volume down 0x1f, play/pause 0x1c). Probe 1.23 uses it. | Owner: test probe 1.23. |
| 2026-10-16 | Stage 4 | Probe 1.23: **all EarPods buttons operate the iPod** (volume +, volume −, play/pause), with the volume bar and the repeats of an Apple Remote. The click wheel volume sets the EarPods volume. | Next: the freeze at a new connection in host mode, then Stage 3 (the real patch with a Settings item). The owner: the UI lag came from a separate patch, not from the USB host probe. |
| 2026-10-16 | Stage 4 | Ghidra: the freeze comes from the USB device task. When VBUS goes away, its stop resets the controller under the host stack, and the UIM then waits forever (0xe8c20); when VBUS comes again, it starts the device mode on the same controller. Probe 1.24 ends the device session before the host start and blocks the device start and stop while host mode runs. | Owner: test probe 1.24 (dock disconnection and connection, Mac connection). |
| 2026-10-16 | Stage 4 | Probe 1.24: **no freeze** at a new connection of the dock or of the Mac. The headphones did not operate after the reconnection. Probe 1.25 starts the route again at the first button press after the new enumeration, and adds two pushes (next track) and three pushes (previous track) of the middle button. | Owner: test probe 1.25. |
| 2026-10-16 | Stage 4 | Probe 1.25: **the headphones operate again after a reconnection**; two and three pushes (next, previous) operate well. The playback stopped completely at the disconnection. Probe 1.26 stops the route in USBAudioTask between two sets and then pauses the player. | Owner: test probe 1.26 (the disconnection: a pause, then Play). |
| 2026-10-16 | Stage 4 | Probe 1.26: **the song pauses at the disconnection.** The headphones start too loud, and at the reconnection the "unsupported device" screen ended the playback. Probe 1.27 shows no USB host messages while host mode runs, and uses a quieter volume curve (half volume −24 dB). | Owner: test probe 1.27. |
| 2026-10-16 | Stage 4 | Probe 1.27: **all as expected.** No "unsupported device" at a reconnection; the song pauses at a disconnection and continues after Play; the volume levels are good. The probe now has all the functions of USB audio out. | Next: Stage 3, the real patch (a Settings item, no tones and no log). |
| 2026-10-17 | Stage 3 | The patch `usb-audio-out` 1.0: Settings > USB-C Audio, the task USBAudioOut, Apple's USB mode manager for On and Off, the automatic route start. Swift and Python tests pass. | Owner: test on the real iPod (Off: sync; On: music, volume, buttons, reconnection; Off: the Mac sees the iPod). |
| 2026-10-17 | Stage 3 | **The patch `usb-audio-out` 1.0 passed all test steps on the real iPod**: Off and sync; On, the music to the EarPods without a button press; the volume and the buttons; a pause at a disconnection and Play after a reconnection; Off and the Mac sees the iPod; On, Off, On again. | USB-C audio out is complete. |
| 2026-10-17 | Stage 3 | The owner: the iPod charges from the dock while USB-C Audio plays. Version 1.1 adds the option "Sample Rate" (44.1 kHz or 48 kHz). | Owner: test 48 kHz. |
| 2026-10-17 | Stage 3 | The owner tested 48 kHz on the real iPod and heard no problems. The patch keeps no log, so the accepted rate is not known. | Version 1.2 shows the rate in Settings. Owner: test it. |
| 2026-10-17 | Stage 3 | Version 1.3: Settings > Main Menu > USB-C Audio puts a switch in the main menu ("USB-C Audio: Off"). Emulator: correct, also with `album-artists`. | Owner: test it on the real iPod. |
| 2026-10-17 | Stage 3 | The owner: the scrolling is a little slower while USB-C Audio is On. Research: Apple's USB host task polls about 1000 times each second; USBAudioTask wakes 83 times each second. Version 1.4 (branch `usb-audio-speed`): 8 ticks for the host task while the route runs, two sets of packets in each wake. Emulator: the poll each 8.17 ms. | Owner: compare the scrolling with version 1.3. |
| 2026-10-17 | Stage 3 | Version 1.4 on the real iPod: still stuttery. Jack music smooth, On without music smooth, USB music stutters at both rates. Version 1.5 measures the scheduling delay of a task with the UI priority, the idle time and the USBAudioTask values each second. | Owner: run the measurement. |
| 2026-10-17 | Stage 3 | Measurement 1.5 on the real iPod: the scrolling uses all free time of core 0. USB music uses about 15 % more of core 0 than jack music (core 0 idle 43 % against 59 %), also about 16 % with the music paused. Apple's fill of 12 packets takes about 1.9 ms, 83 times each second. | Research 0x1e3064, then a faster fill. |
| 2026-10-17 | Stage 3 | Ghidra: at 44.1 kHz Apple's fill only copies or clears about 2 KB for each set; it cannot cost 16 %. Version 1.6 counts the USB interrupts, the siTD errors and the host task messages each second. | Owner: run the measurement again. |
| 2026-10-17 | Stage 3 | Measurement 1.6: 1 USB interrupt each second, 0 errors; Apple's fill takes about 129 ms in each second (13 % of core 0), also when paused. Version 1.7 replaces Apple's fill with a fast fill in the patch while the route runs. | Owner: listen for correct music, test the scrolling, and send the log. |
| 2026-10-17 | Stage 3 | Version 1.7 on the real iPod: the sound correct, but the fast fill never ran. The probable cause is the converter flag of 0x1e2f60, set when the route starts. Version 1.8 uses the fast fill when the two rates are equal, and records the rates. | Owner: test 1.8. |
| 2026-10-17 | Stage 3 | Version 1.8 on the real iPod: the option Sample Rate was still 48 kHz. Apple's rate converter 44.1 → 48 kHz runs on each packet, also while paused, and uses about 12 % of core 0. | Owner: test again with 44.1 kHz. |
| 2026-10-17 | Stage 3 | Version 1.8 at 44.1 kHz on the real iPod: the fast fill makes all packets; the fill uses about 3 % of core 0 (13 % before); core 0 idle 51–55 % during USB music (jack 58–60 %). The owner: the scrolling better, the sound correct. 48 kHz still uses Apple's converter (about 12 % of core 0). | Owner: decide the next step. |
| 2026-10-17 | Stage 3 | Version 1.9: the measurement code is removed; the fast fill, the 8-tick host wait and the two sets per wake stay. The option Sample Rate warns: select the rate of the music in the library, because Apple's converter causes performance drops. | Owner: test 1.9, then decide the merge to main. |
| 2026-10-17 | Stage 3 | Version 1.9 on the real iPod: the headphones and the hub were not found; after a new connection and On again the iPod crashed. The code of 1.9 is 1.8 without the measurement; the changes since 1.3 run only while the music route runs. | Find the cause: repeat the test, then compare with 1.3. |
| 2026-10-27 | Stage 3 | Version 1.9 on the real iPod again: works well (the owner: "works great"). The cause of the failure of 2026-10-17 is not known. | None. |
