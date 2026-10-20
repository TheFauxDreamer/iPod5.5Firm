# Plan: support for the 3-in-1 USB-C adapter (USB-C power, 3.5 mm, USB-A)

Status: plan only (2026-10-20). No code exists yet. Do the steps in sequence.

## Context

The owner has a USB-C adapter with three sockets: a USB-C power input, a 3.5 mm jack and a USB-A socket. The owner wants two functions with USB-C Audio On:

1. The 3.5 mm jack of the adapter plays the music of the iPod.
2. A charger in the power socket of the adapter supplies 5 V to the adapter and charges the iPod. (Owner decision: the iPod does not supply the 5 V itself. That case needs the hardware mod in `docs/usb-c-power-mod.md`.)

### Why the adapter does not operate now

- `usb-audio-out` 1.9 (`patches/usb-audio-out/usb_audio_out.c:209`, `parse_audio`) accepts only USB Audio Class 2 (interface protocol 0x20), 16-bit stereo, with a packet of 192 bytes or more. The EarPods are UAC2.
- The 3.5 mm jack of most 3-in-1 adapters is a small UAC1 sound card behind a hub. UAC1 has no clock source. It sets the rate with a request to the endpoint, and it reads the volume range with GET_MIN and GET_MAX, not with RANGE.
- The first test of this adapter type (`re/usb-host.md`, 2026-10-07, probe 0.1.56) occurred before the fixes for the interrupt, the hubs and the periodic insert. Thus no result for the current code exists.
- The power path is probably correct already: the iPod charged from the dock while USB-C Audio played (2026-10-17). The adapter must give the charger voltage to its USB-C plug. Only a test shows this.

### Answer to the question "Is the process documented?"

No. The documents record the research for one device (the USB-C EarPods) in the sequence of the work: `USB-AUDIO-OUT.md`, `patches/usb-host-probe/FINDINGS.md`, `re/usb-host.md`. They give no procedure to add a different device and no list of the supported devices. This plan adds that document (step 6).

## Open risk before the work

`usb-audio-out` 1.9 is on main, and it **failed** its real test (2026-10-17): the headphones and the hub were not found, and the iPod crashed after a new connection. The adapter work starts from 1.9. Thus do step 0 first. If 1.9 still fails with the dock and the EarPods, a failure with the adapter does not show the cause.

## Steps

### Step 0: test the base (owner, real iPod)

1. Install `usb-audio-out` 1.9 from main.
2. Connect the dock and the EarPods. Set USB-C Audio to On.
3. Record the result. If 1.9 fails, find the cause first (compare with 1.3, as `usb-speed-branch` says).

### Step 1: the branch

- Make the branch `usb-adapter` from main in the worktree `../iPod5.5Firm-usb-adapter`.
- Build with `APP_NAME="iPodFirm USB-C Adapter Test" mac/scripts/build-app.sh`. Do not overwrite `/Applications/iPodFirm.app`. Check the `RELEASE` default of the script on the branch before the build.
- Save a memory for the branch (as `usb-vbus-test`), and add it to `MEMORY.md`.

### Step 2: read the adapter descriptors (no code change)

The probe `usb-host-probe` 1.29 already logs and decodes each configuration descriptor. `USBProbeLog.swift:395–404` already decodes the UAC1 descriptors.

1. Disable `usb-audio-out` (the two patches conflict). Install `usb-host-probe`.
2. Connect a charger to the power socket of the adapter. Connect wired headphones to the 3.5 mm jack.
3. Select "Start the Probe Without Music". Connect the adapter.
4. Use "Copy Log" and give the log to Claude.
5. Record in `re/usb-host.md` and `FINDINGS.md`: the hub (VID:PID), the sound card (VID:PID, device class), the audio class (1 or 2), each alternate setting (channels, bits, subframe size, rates, packet size, sync type), the units (feature unit and its controls), the HID interfaces, and OTGSC "VBUS valid".

Gate: if the sound card does not enumerate, examine the log first. Do not write the driver code before the descriptor is known.

### Step 3: the code in `patches/usb-audio-out/usb_audio_out.c` (version 1.10)

Change only the parts that the descriptor needs. Expected changes for a UAC1 card:

1. `struct audio`: add `uac` (1 or 2) and the list of the UAC1 rates.
2. `parse_audio`: accept protocol 0x00 (UAC1) and 0x20 (UAC2).
   - UAC1 FORMAT_TYPE I: `bNrChannels` b[4], `bSubframeSize` b[5], the rates from b[8] (3 bytes each).
   - UAC1 output terminal: 9 bytes (UAC2: 12). Its source is b[7].
   - Use the volume unit only if it is a feature unit (subtype 6) with a volume control.
   - Packet check: 180 bytes for 44.1 kHz, 192 bytes for 48 kHz, not always 192.
   - Accept the sync types synchronous and adaptive. An asynchronous endpoint needs the feedback endpoint: do it only if the descriptor shows it.
3. `music_start` (line ~1179): for UAC1, send SET_CUR sampling frequency to the endpoint (request type 0x22, wValue 0x0100, wIndex = endpoint, 3 bytes). Use the rate of the option if the card has it, else the other rate. GET_CUR from the endpoint for the value in Settings.
4. `volume_start` (line ~769): for UAC1, read GET_MIN (0x82) and GET_MAX (0x83), 2 bytes each, not RANGE. SET_CUR volume (`volume_send`) is the same in UAC1 and UAC2.
5. `parse_hid` and the buttons: no change. A card without HID buttons gives `hids = 0`.
6. The EarPods path (UAC2) must stay the same.

`patch.json`: `version` 1.10. Measure `size` with `swift test --filter testPatchSizes`. Change `description` and the "Use USB-C Audio" steps: "USB audio devices (UAC1 and UAC2)", and a step for the charger in the adapter. The app UI is the existing Settings item and the Patches pane text; no new pane is necessary.

If the probe must test a UAC1 stream first, change `parse_audio` in `patches/usb-host-probe/usb_host_probe.c:672` in the same way (version 1.30).

### Step 4: offline check

Compile `parse_audio` on the Mac with the real descriptor bytes from the log (a script in the scratchpad, not committed). It must give the interface, the alternate, the endpoint, the packet size and the volume unit of the adapter. It must also give the old result for the EarPods descriptor in `FINDINGS.md`.

### Step 5: tests

- `cd mac && swift test` (with `IPODFW_IPSW`) and `uv run pytest`: `testPatchSizes`, `testPatchVersions`, `testPatchVersionLetters`, `testUSBAudioOutConflictsWithProbe`.
- Emulator: the firmware starts, Settings > USB-C Audio On and Off operate. (The emulator has no USB.)
- Real iPod, with the charger in the adapter:
  1. Off: sync with the Mac.
  2. On: the music plays in the 3.5 mm jack, without a button press.
  3. The click wheel changes the volume.
  4. The iPod shows the charge symbol during the music.
  5. Disconnect the adapter: the song pauses. Connect it again and push Play: the music continues.
  6. Off: the Mac sees the iPod.
  7. The EarPods with the dock: no change from 1.9.

### Step 6: the documents (same commit as the code, in STE)

- **New `docs/usb-devices.md`:** the procedure to add a USB audio device (steps 2–5 of this plan in a general form), the descriptor fields to record, the UAC1 and UAC2 differences, the limits (one port, no 5 V from the iPod, full speed only, asynchronous endpoints), and a table of the devices with their test status (EarPods, the 3-in-1 adapter).
- `docs/README.md`: add the new document to the table "Documents" and to "Where to start".
- `docs/modifications.md` § usb-audio-out: effect, size, logic, test status.
- `docs/safety.md`: test status.
- `re/usb-host.md` (the results first), `patches/usb-host-probe/FINDINGS.md` (test table, status), `USB-AUDIO-OUT.md` (results table).
- `docs/firmware-functions.md`: only if a new firmware address is used.
- `docs/patch-system.md` and `docs/firmware-format.md`: only if the size change affects the free space table or the memory map.
- `README.md`: the text about USB-C Audio, if it says "UAC2 only".

## Verification

- All Swift and Python tests pass.
- The offline parse check gives the correct values for the adapter and for the EarPods.
- The real-iPod steps of step 5 pass. Record each result in `re/usb-host.md`, `FINDINGS.md`, `docs/safety.md` and `docs/modifications.md`.
- Merge into main only after the real test and the owner's decision. Keep the branch also if a gate stops the work.
