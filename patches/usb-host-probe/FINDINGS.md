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
| Isochronous transfers | **Works (probe 1.3, 2026-10-10): a 1 kHz tone in the USB-C EarPods, 5105 frames, 0 errors** |
| The music of the iPod to the EarPods | **Works (probe 1.5, 2026-10-10)**; the UI is very slow, and the album art in Now Playing does not load. Probe 1.6: still slow; the dock reconnection froze the iPod. Probes 1.7 and 1.8 (interrupt wait): restarted after the tone. Probe 1.10: scrolling correct; the UI stutters only where the Now Playing art must show, and the art is missing. Probe 1.11: no storage driver, art still missing. Probe 1.12: the art is also missing when the probe is installed but not started. Probe 1.13 (no trace hooks), installed and not started: **the art loads**. Next: the art with the probe started (host mode) | Apple's USB audio source (Wadia path) gives the decoder PCM to USBAudioTask; the probe sends its packets with the siTDs. | The UIM entries are stubs (0xd4820, 0xd4828). The probe makes its own siTDs in the frame list and sends a 1 kHz tone for 5 s. |

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
- The firmware switches pin 18 with 0x264d78 (PCF50605 D2REGC1: 0xf8 on, 0x18 off). The host start already turns it on (the UIM init 0x97300 calls 0x264d78(3)). The root hub driver already sets PP (PORTSC bit 12, 0x96a24). Refer to [re/usb-power.md](../../re/usb-power.md) (branch `usb-vbus-test`).
- The USB-C mod probably connects VBUS to the USB power input of the iPod, not to pin 18. This is not measured. The firmware has no other output that it can switch to VBUS. The VBUS test (probe 1.29) measures it.
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
| Probe 1.2 (iPodFirm 0.1.90) | Dock; USB-C EarPods | No tone and no audio record. The log was full (511 records) before the audio test. The dump of configuration 1 had 16 zero bytes at the start (old cache data from the earlier 4-byte reads of the same buffer), thus the device finder found no audio interface. | The 0x1xxxxxxx window is in the cache, and the 0x9xxxxxxx window is not. Probe 1.3 reads the buffers directly, finds the device at the completion and keeps 16 log records for the test. |
| Probe 1.3 (iPodFirm 0.1.91) | Dock; USB-C EarPods | **The owner heard the 1 kHz tone in the EarPods.** Audio records: device address 67, interface 1 alternate 2, endpoint 2 OUT, 192 bytes, clock 9. SET_INTERFACE, SET_CUR 48000 Hz and SET_INTERFACE 0 correct. 5105 frames sent, 0 errors (approximately 5.1 s). The log kept space for the records (503 records). | **Stage 2 works on the real iPod.** Full-speed siTDs through the transaction translator of the controller (hub 0, port 1), behind the dock's hub, with the probe's own control queue head. |
| Probe 1.4 (iPodFirm 0.1.92) | Dock; USB-C EarPods; a song | No music; the song stayed at 0:00; slow menus. Route on (+0x5a = 1), SET_CUR 44100 correct, 42 204 packets, 0 underruns. | The packets were silence: 0x1e3064 takes the music only if the iAP flag 0x1081dff6 is set. The slow menus came from the log writes. Probe 1.5 corrects both. |
| Probe 1.5 (iPodFirm 0.1.93) | Dock; USB-C EarPods; a song | **The music played through the EarPods.** The UI was very slow, and the album art in Now Playing did not load. Status: 38 892 packets, 0 underruns, 1406 packets with sound; USB buffers 2, the queue moves, ready flag 1, 44 100 Hz without conversion. The log was full after the second status. | The chain works. Probable cause of the slow UI: the wait of the probe called the 1 ms sleep many times in each 12 ms in USBAudioTask; the sleep yields in a loop. Probe 1.6 sleeps one time each cycle and measures the sleeps. |
| Probe 1.6 (iPodFirm 0.1.94) | Dock; USB-C EarPods; a song | Music, but the UI still very slow, no album art. A disconnection and connection of the dock froze the iPod. Status: 15 780 packets, 0 underruns, 408 packets with sound; 1313 sleeps, 14 924 ms requested, 14 991 ms passed. | The sleep timing is exact, but the UI is slow: the sleep 0x11c9fc probably yields in a loop, thus USBAudioTask keeps the CPU. Most packets are silence: the decoder also gets too little CPU (0x1a2924 gives a silence buffer when the decoder is not ready). Probe 1.7 blocks on the interrupt event, as Apple's device code does. |
| Probe 1.7 (iPodFirm 0.1.95) | Dock; USB-C EarPods | The iPod restarted (Apple logo) after the tone, before the second double beep. The owner: the music of probe 1.6 sounded correct. | The interrupt wrapper called the event signal 0xd1e70 in the interrupt; it makes a kernel request when a task waits. Probe 1.8 posts the signal with 0xadbdc, as the host handler does. The low count of packets with sound in 1.6 came from the full log (only the first 16 s). |
| Probe 1.8 (iPodFirm 0.1.96) | Dock; USB-C EarPods | The iPod restarted after the tone again. The log has the records up to "music route on": the restart came after the stream started, during the log write. | The interrupt path ("interrupt on complete", about 166 deferred calls each second with the calls of 0xffd1c) is the cause. Emulator profile: the sleep 0x11c9fc blocks (less than 1.5 % of the CPU in its loop); the copy loop of the probe took 19 %, Apple's packet fill about 15 %. Probe 1.9: back to the sleep, a 32-bit copy, the volume −20 dB on the EarPods, and a CPU record with the microsecond timer. |
| Probe 1.9 (iPodFirm 0.1.97) | Dock; USB-C EarPods; a song | No restart. The music played; the UI still lags; the album art does not load. The EarPods buttons do not change the volume (they send HID to the host). The disconnection and connection of the dock still froze the iPod. CPU record: probe copy 1616 ms (1.1 %), Apple's packet fill 4316 ms (2.8 %) of 152 s; 0 underruns; 118 871 of 152 592 packets with sound. | The music path is not the cause of the lag. The flag 0x1081dff6 is not the cause (only 0x1e2f74 reads it; 0x1d56e0 sets it from a file in iPod_Control/Device). Probe 1.10 logs the idle time of the CPU (the statistics of the idle routine 0xded04) for each phase. |
| Probe 1.10 (iPodFirm 0.1.98) | Dock; USB-C EarPods; a song | Scrolling correct. The UI stutters only when the album art of Now Playing must show; the art does not show. No idle records: the owner armed the probe again, and the log was reset. | The problem is in the Now Playing art path, not in the CPU load. Hypothesis: the card slot of the dock (2537:1081) gets the storage driver, and the iPod enters the photo import state of the Camera Connector, which uses the same image library (ithmb) as the album art. Probe 1.11 gives no driver to storage devices. |
| Probe 1.11 (iPodFirm 0.1.100) | Dock; USB-C EarPods; a song | The Now Playing art still does not load. Idle of core 0: 96.8 % before the host start, 87.0 % host mode, 57.0 % music route before the song, 26.6 % during the song; core 1 72.4 % idle in the last interval. The dock disconnection stopped the music (reason 1). | Not the photo import state. The host mode takes about 10 % of the CPU and the music route about 30 % more. Ghidra: the art comes from ArtworkLoadTask (0x205db4); probe 1.12 traces each of its steps. |
| Probe 1.12 (iPodFirm 0.1.101), run 1 "without music" | Dock; EarPods; music on the headphone jack | The art still does not load. Trace: ArtworkLoadTask woke 11 times, the gate was granted (step 3 = 1), but its request queue was always empty: no lookup (steps 7–13) ran. The owner: the art also does not load with the probe installed and not started; it loads when the probe is removed. | Not host mode and not the music route: the installed patch itself. With the owner's patches the image ends at about 0x7F1D30 with the probe (above the old limit 0x7F0000) and at about 0x7EE3A0 without it. Hypothesis: the firmware uses the RAM above 0x7F0000 (the old margin) at run time, probably for the art. The app setting "Layout" can select the old limit 0x7F0000 for a test. |
| Probe 1.12, owner tests (2026-10-15) | Different patch sets, margin 32 KB and 64 KB | The art is missing only when `usb-host-probe` is in the firmware, also when the probe is not started; the margin does not change it. | Not the margin. With the probe not started, only `hook_event` and the 1.12 hooks (art trace, output) run (the hook analysis below). Probe 1.13 removes the 1.12 hooks. |
| Probe 1.13 (iPodFirm 0.1.103), not started | Normal use | **The Now Playing art loads.** | The 16 hooks of 1.12 (art trace, output) stopped the art. Probable cause: Apple's code in 0x205db4 uses register values that it expects the called functions to keep; the C wrappers do not keep them. Lesson: do not put C wrappers on calls inside Apple's task loops; use naked wrappers that keep r1–r3 and r12, or none. |
| Probe 1.13, started (2026-10-15) | "Start the Probe Without Music", then Now Playing | **The art is missing**, also without the music route. | The cause is in the host mode, not in the music route. Ghidra: eight gates of the art load (re/usb-host.md); static analysis cannot show which gate closes. Probe 1.14 logs the gates (tags 62 and 63), with no new hooks. |
| Probe 1.14 (iPodFirm 0.1.104), started (2026-10-15) | "Start the Probe Without Music", a song, Now Playing | The art is missing. In each record: the capacity 0x100000, the library open, + 0x78 = 0 and + 0xc = 0 (no track in the art cache list), also with the song. The photo import state is 1 also before the host start. | Gate 3 is closed: no track reaches the art cache list. Ghidra: the path 0x87cec → 0x1bfe84 (library queue, event 0x55000000) → 0x1c020c → 0x1bfe18 → the cache queue → 0x206860. Probe 1.15 counts the queues (tag 64). |
| Probe 1.15 (iPodFirm 0.1.105), started (2026-10-15) | The same test | The art is missing. Tag 64 in each record: library queue 0, cache queue 0, 1 cache entry, enabled. After the song starts, + 0x71 changes from 1 to 0 (the task ran). | The request passes both queues; the art lookup 0x205e64 adds nothing. Ghidra: the lookup needs the ArtworkDB handle (database + 0xd2c); the reload 0xb4fe4 clears it. Probe 1.16 logs the handle (tag 65). |
| Probe 1.16 (iPodFirm 0.1.106), started (2026-10-15) | The same test | The art is missing. Tag 65 in each record: the ArtworkDB handle 0x13df3670 (+ 0xd2c = + 0xd14), app + 0x484 = 0, + 0x489 = 1, + 0x48a = 0; USB device state 0, then 1 while the song plays. | No database reload; the ArtworkDB stays open. The reload hypothesis is wrong. Probe 1.17 tests the ArtworkDB object and the lookup (tag 66). |
| Probe 1.17 (iPodFirm 0.1.107), started (2026-10-15) | The same test | The art is missing. Tag 66 in each record: first word 0x6974696c, 5218 entries, index 0x10a28278, the list lookup and the index lookup find the first entry. | The ArtworkDB and step 1 of 0x205e64 are correct. Probe 1.18 tests the whole step 0x205e64 (tag 67) and adds a baseline action without the host start. |
| Probe 1.18 (iPodFirm 0.1.108), baseline "Record the Art State Without USB Host" (2026-10-15) | No host start; a song; Now Playing | **The art is also missing.** The test calls of 0x205e64 add the art formats (+ 0x78 0 → 1 → 2 → 3); after the song starts, + 0x78 stays 3. | The cause is not the host mode. It is in the part of the probe that runs in each mode: the tones, the 32 KB log buffer and the log writes. Each log write called 0x1a0120 and 0x19ff0c. 0x19ff0c is not a disk flush: it makes each user of the memory cache manager give back its memory, and Apple calls it only before the sleep and the disk mode. 1.13 not started wrote no log, and the art loaded. Probe 1.19 does not call 0x19ff0c. |
| Probe 1.19 (iPodFirm 0.1.109), baseline (2026-10-15) | No host start; songs; Now Playing | **The art loads.** + 0x78 grows from 3 (the three test calls) to 6 and 8 while songs play. The UI is still a little slow. | **Root cause:** the probe called 0x19ff0c after each log write. The only change from 1.18 is the removal of that call. Lesson: do not call a firmware function from its name in an old note; check what it does. |
| Probe 1.19, host mode "Start the Probe Without Music" (2026-10-15) | Host start; songs; Now Playing; then a connection to the Mac without a restart | **The art loads.** + 0x78 grows from 3 to 7 and 10. The connection to the Mac froze the iPod; 128 records reached the disk. | The art problem is solved in host mode too. The freeze at a new connection in host mode is still open (as the dock reconnection). |
| Probe 1.20 (iPodFirm 0.1.110), music route (2026-10-15) | "Start the Probe at the Next Restart", the dock and the USB-C EarPods, songs, Now Playing | **The music plays through the EarPods and the art loads.** 80 436 packets (80 s), 0 underruns; + 0x78 grows to 8; the probe copy 0.83 s and Apple's packet fill 2.2 s of 80 s. Idle of core 0: 26–44 % during the music. | Stage 4 and the art work together. In the 1.19 baseline without host mode, the idle of core 0 during a song was 18–38 %; thus the playback itself uses most of the CPU, not the USB path. |
| Probe 1.21 (iPodFirm 0.1.111), music route (2026-10-16) | Songs; the click wheel volume; the EarPods buttons | **The EarPods volume follows the click wheel, with no gaps.** RANGE −60 to 0 dB (0.5 dB); 51 SET_CUR, all correct. Interface 3: report ID 1, bits play/pause 0, volume + 1, volume − 2, voice 3; reports `01 04`, `01 01`, `01 00`. Interface 4: vendor page, no buttons. The log was full (511) after the button reports. | The volume works. The button decode is correct. Probe 1.22: the buttons as iPod controls through key events. |
| Probe 1.22 (iPodFirm 0.1.112), music route (2026-10-16) | The EarPods buttons | **The buttons did not operate the iPod.** Each report decoded correctly; each post (0x13d6d4) returned 1; no record of the UI hook. | A `MsgS` message to the app target does not reach the key handler 0x1d81cc. The real key path is 0x1ac198 (`kDwn`, `kUp `), with the Simple Remote codes (table 0x63ef30). Probe 1.23 uses it. |
| Probe 1.23 (iPodFirm 0.1.113), music route (2026-10-16) | The EarPods buttons, songs | **All buttons operate the iPod as expected** (volume +, volume −, play/pause). Log: 12 volume − and 3 volume + pushes and releases through 0x1ac198 (then the log was full); 0 underruns. | The volume and the buttons are complete for the probe. |
| Probe 1.24 (iPodFirm 0.1.115), music route (2026-10-16) | Dock disconnection, reconnection; then the Mac | **No freeze** at the reconnection of the dock or at the Mac connection. Tag 74: no device session before the host start; the device start at the reconnection was blocked. The music paused at the disconnection; after the reconnection, no sound and no controls. | The freeze is solved. The route starts only one time; probe 1.25 starts it again after a reconnection. |
| Probe 1.25 (iPodFirm 0.1.116), music route (2026-10-16) | Two and three pushes; dock disconnection and reconnection | **The headphones operate again after the reconnection** (after a button press). Two pushes (next) and three pushes (previous) operate well. At the disconnection the playback stopped completely. The log was full before the disconnection. | Probable cause: the stop ran in the UIM task while USBAudioTask held decoder packets. Probe 1.26 stops in USBAudioTask and then pauses. |
| Probe 1.26 (iPodFirm 0.1.117), music route (2026-10-16) | Dock disconnection and reconnection | **The song pauses at the disconnection** (tag 75: playing, then paused). The headphones start too loud (the owner turned the volume down at once). At the reconnection the iPod shows "unsupported device", and that screen ends the playback. | The message comes from add device (0xd377c, error 0x68c for the devices without a driver) through 0xd9cec. Probe 1.27 skips the message while host mode runs, and uses the curve −48 · (1 − v/256) dB. |
| Probe 1.27 (iPodFirm 0.1.118), music route (2026-10-16) | Start, volume, disconnection, reconnection, Play | **All as expected.** No "unsupported device"; the song pauses and continues; the volume levels are much better. | The probe is complete for Stage 4. |

## The causes found

1. **No host mode without a Camera Connector.** The stock firmware starts the host stack only after iAP lingo 6 with a Camera Connector (0x1fb50c). The probe calls the host start 0x2860e8 directly.
2. **The USB interrupt belongs to the device driver.** The device driver installs its handler 0xcd8e0 for source 20 after each start. The UIM install of 0xffd1c (0x9741c) then has no effect. The probe removes the device handler (0x127888, 0x1277d0), installs 0xffd1c (0x18a83c) and enables the source.
3. **External hubs are refused** (fixed in the probe; the dock's hub then works). In "add device" 0xd377c, a device of class 9 is accepted only if `g[0] > 1`, or if `g[1] < 3` and (`g[0] != 0` or `g[1] == 0`). g is the USB global block (RAM 0x1083e0f8); g[1] counts the loaded hubs (the root hub makes it 1). g[0] is 0 from the start, and no code sets it. The refusal reports error 0x673 or 0x67d (0xd9cec), and the photo import screen says "unsupported device". The probe sets g[0] = 2.
4. **Firmware bug in the periodic insert** (0xf5c80): the frame list word comes from r1, but the callers give the queue head in r0. No interrupt endpoint (for example the status change endpoint of a hub) is polled. The probe sets r1 = r0 at both calls (0x9761c, 0x96d14).
5. **The emulator allows reads that the real iPod does not.** A read in the 0x90000000 window (the uncached view of the RAM, RAM | 0x80000000) stopped the probe on the real iPod. Read RAM only through 0x10000000–0x14000000.

6. **The probe read DMA buffers through the data cache** (corrected in probe 1.3: it reads 0x9xxxxxxx addresses directly). The probe reads RAM through 0x10000000, and the cache keeps the lines. When the controller then writes new data to the same buffer, the probe reads the old lines. Example: the composite driver put configurations 2 and 3 into the same buffer as configuration 1, and the dumps showed old bytes. The firmware itself reads through the 0x90000000 window and gets correct data. Only the first read of a buffer is reliable.

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

## The hooks in normal use (analysis of 2026-10-15)

| Hooks | Run without the probe start? |
|---|---|
| `hook_event` (0x1d8260 in the UI event handler 0x1d81cc) | Yes, at each event. 0x1d8570 has 2 arguments; its result is not used; the hook reads the trigger file one time. |
| Art trace (14 sites in 0x205db4) and `hook_output_make` (0x18c770, 0x1b8054), version 1.12 only | Yes. Removed in 1.13. |
| `hook_port_status`, `hook_chip_check`, `hook_irq_install`, `hook_add_device`, `hook_periodic_insert`, the `b` hooks 0xcb118 and 0xcba54, the UIM and class driver table words | No: USB host mode only. |
| `hook_usb_send`, `hook_usb_wait`, `hook_usb_wait_if_sent` (0x132038) | No: only when USBAudioTask streams. |
| `hook_device_start`, `hook_device_stop` (the device task 0x170f2c, version 1.24) | Yes, at each USB power change, but they call the originals until the probe starts host mode. |

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
| 0x264d78 | Accessory power of dock pin 18 (1 off, 3 on at 3.3 V); the UIM init calls it with 3 |
| 0x96a24 | Root hub port power (PORTSC bit 12) |

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

0. Branch `usb-vbus-test`: the VBUS test (probe 1.29, trigger '3'). It finds if the iPod can supply VBUS to the EarPods with no hardware change. Owner: run "Start the VBUS Test at the Next Restart" with no cable on the iPod. Refer to [re/usb-power.md](../../re/usb-power.md).

1. Done: the configuration of the EarPods (UAC2, refer to "The USB-C EarPods").
1a. Done: the probe 1.3 played a 1 kHz tone to the EarPods (2026-10-10).
1b. Done: the probe 1.5 played the music through the EarPods (2026-10-10).
1c. Done: probe 1.13 installed and not started: the art loads. Probe 1.13 started without the music route: the art is missing.
1d. Done: probe 1.14: no track reaches the art cache list in host mode.
1e. Done: probe 1.15: the request queues are empty; the art lookup finds no art.
1f. Done: probe 1.16: the ArtworkDB handle stays set; no reload.
1g. Done: probe 1.17: the ArtworkDB and its lookup are correct in host mode.
1h. Done: probe 1.18 baseline: the art is also missing without the host start.
1i. Done: probe 1.19 baseline: the art loads. The cause was 0x19ff0c.
1j. Done: probe 1.19 in host mode: the art loads.
1k. Done: probe 1.20 with the music route: the music and the art work.
1m. Done: probe 1.21: the click wheel volume on the EarPods works; the buttons decode.
1n. Done: probe 1.22: the key posts to the app did not reach the key handler.
1o. Done: probe 1.23: the EarPods buttons operate the iPod (the remote key path 0x1ac198).
1p. Done: probe 1.24: no freeze at a new connection (the device task is blocked while host mode runs).
1q. Done: probe 1.25: the route again after a reconnection; two and three pushes operate.
1r. Done: probe 1.26: a pause at the disconnection.
1s. Done: probe 1.27: all as expected.
1t. Done: Stage 3, the patch `usb-audio-out` 1.0 (the code of probe 1.27, Settings > USB-C Audio). Real iPod (2026-10-17): all test steps passed. The UI lag is closed: the owner found that a separate patch caused it, not the USB host probe (2026-10-16).
1l. Later: the freeze when a computer or the dock connects in host mode; the volume (iPod volume to the feature unit, HID buttons; done in 1.21–1.23); the UI lag (closed: a separate patch); then Stage 3. Earlier item: probe 1.20 (1.19 with corrected test steps: wait 15 s, then restart; do not connect the Mac in host mode) with the music route ("Start the Probe at the Next Restart"). Then the freeze when a computer or the dock connects in host mode, and the UI lag.
2. Optional: read configurations 2 and 3 and the clock ranges (UAC2 GET RANGE). The external test above makes this less important: the Stage 3 driver can try 44.1 kHz and use 48 kHz if the EarPods refuse it. The probe must read each buffer only one time, or clean the cache first.
3. Optional bench test of the minimum voltage of the EarPods (refer to the hardware section).
4. Then Stages 2 and 3 of USB-AUDIO-OUT.md: the isochronous UIM entries and a USB audio class driver.
