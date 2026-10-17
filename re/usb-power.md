# USB power for USB-C headphones: can the iPod supply VBUS?

This note records the research on one question: can the iPod 5.5G supply VBUS to USB-C headphones through the USB-C mod, with no hardware change? The branch is `usb-vbus-test`. The USB host work is in [usb-host.md](usb-host.md) and in [patches/usb-host-probe/FINDINGS.md](../patches/usb-host-probe/FINDINGS.md).

## The problem

USB-C audio operates (the patch `usb-audio-out`, real iPod 2026-10-17). But the headphones get VBUS only from an external supply: a dock with a power supply, or an adapter with a charger. The iPod Camera Connector got 3.3 V from dock pin 18 and changed it to 5 V with its own step-up converter.

A path with no hardware change exists only if one of these is true:

1. The USB-C mod connects dock pin 18 (3.3 V accessory power) to the USB-C VBUS.
2. The ARC USB controller drives a VBUS switch: PORTSC bit 12 (PP), or OTGSC bit 1 (VC, "VBUS charge").
3. A GPIO or a PMU regulator in the Camera Connector path connects a supply to the USB power input (dock pin 23).

## Static results (Ghidra, 2026-10-17)

| Address | Function | Evidence |
|---|---|---|
| 0x264d78 | The accessory power (dock pin 18). Argument 1: off. Argument 3: on. Argument 2: PMU mode 2 (the meaning is not known). It writes the PMU regulator through 0x283360(2, 0x18, mode) and sets the GPIO pins 0x6a, 0x6b and 0x21/0x22 (or 0x6a/0x6b) with 0x282910. Mode 1 makes the pins outputs with the value 0. Mode 3 gives them the functions 3 and 4. It does nothing if 0x265c1c returns 0 (the hardware ID is not 4–12). | Static |
| 0x283360 | Writes one PMU regulator: (regulator, voltage code, mode). The register value is `voltage \| mode << 5`. On the PMU type 3, regulator 2 is register 0x25. On the PMU type 2, regulator 2 is register 0x27. | Static |
| 0x283704 | The PMU type. It reads PMU register 0 (the ID). ID 0x24: type 2. Other ID: type 3. An I²C error: type 1. | Static |
| 0x283634 | Writes PMU registers through I²C (0x282f58, device address 8). | Static |
| 0x264d78 callers | 0x97300 (the UIM init, with 3), 0xfebf8 (a task, with 3 when its state is 3), 0x1a6400 (with 1, 2 or 3), 0x10148c (a serial task: 1, then a wait of 2000 ms). | Static (FindXrefs) |
| 0x96a24 | Root hub port power: sets or clears PORTSC bit 12 (PP). The root hub request SET_FEATURE PORT_POWER (0xd26b0, feature 8) calls it with 1. | Static |
| 0x97300 | The UIM init writes PORTSC only one time: `PORTSC & 0xffffffd5 \| 0x1000000` (PFSC, full speed forced). It does not write OTGSC. | Static |
| 0x2666f4, 0x266840 | Read OTGSC bit 11 (B-session valid) as "USB power present". | Static |

The PMU of the iPod Video is the PCF50605. Rockbox `accessory_supply_set` (`firmware/target/arm/ipod/powermgmt-ipod-pcf.c`) writes PCF5060X_D2REGC1 (register 0x25) = 0xf8 for on (3.3 V) and 0x18 for off. 0x264d78 writes the same values: 0x18 | 7 << 5 = 0xf8 for mode 3, and 0x18 | 0 << 5 = 0x18 for mode 1. Thus 0x264d78 is Apple's accessory power switch.

Conclusions:

- The host start already turns on the 3.3 V of pin 18 (0x97300 → 0x264d78(3)). The probe and `usb-audio-out` both use this host start.
- The root hub driver already sets PP (0x96a24). The earlier logs show it: PORTSC 0x28001205 has bit 12.
- No Apple code sets OTGSC bit 1 (VC). On the ARC controller, VC charges VBUS through a resistor for the session request protocol. It gives only a very small current.
- The firmware has no other output to VBUS. Thus, if the headphones did not operate with no external supply, the cause is the hardware: the USB-C mod does not connect pin 18 to VBUS.

## The VBUS comparators of the controller

The ARC (ChipIdea) controller compares VBUS with fixed levels and shows the result in OTGSC. Thus the probe log gives a measurement also with no meter.

| OTGSC bit | Name | Set when VBUS is |
|---|---|---|
| 9 (0x200) | A VBUS valid | above approximately 4.4 V |
| 10 (0x400) | A session valid | above approximately 0.8–2.0 V |
| 11 (0x800) | B session valid | above approximately 0.8–4.0 V |
| 12 (0x1000) | B session end | below approximately 0.2–0.8 V |

Thus 3.3 V on VBUS sets bits 10 and 11, but not bit 9. Until this branch, the log decoder of iPodFirm showed bits 10 and 11 with the names interchanged. The branch `usb-vbus-test` corrects this.

## The VBUS test (usb-host-probe 1.29)

iPodFirm writes '3' to `iPod_Control/iTunes/iPodFirmUSBProbe` ("Start the VBUS Test at the Next Restart"). At the first button press after the restart, the probe starts host mode as for '1'. Then it does the steps below. Before step n, it gives n short high beeps. In each step, it logs OTGSC, PORTSC and the GPIOL input (bit 0x10: the USB power pin) one time each second (tag 76).

| Step | State | Time |
|---|---|---|
| (info) | The PMU type (0x283704) and the hardware ID (0x265164) | — |
| 1 | Apple's host mode state: the accessory power on, PP as the root hub set it | 10 s |
| 2 | The accessory power off (0x264d78(1)); after the step, on again (0x264d78(3)) | 10 s |
| 3 | PP inverted; after the step, as before | 10 s |
| 4 | OTGSC VC on; after the step, off | 10 s |
| 5 | All on: the accessory power, PP and VC. The owner connects the USB-C EarPods directly to the iPod. If they enumerate, the probe plays its 1 kHz tone (`audio_test`). | 30 s |

Then the probe writes the log and gives two short low beeps. The UI task does not react for approximately 90 s.

## How to read the result

- **Pin 18 reaches VBUS:** in step 1, bits 10 and 11 are set. In step 2, they are clear. Then a direct connection is possible, but VBUS is only 3.3 V. The EarPods must operate at 3.3 V.
- **Pin 18 does not reach VBUS:** bits 9–11 are clear in all steps, and bit 12 is set. The EarPods do not enumerate in step 5. Then a hardware change is necessary.
- **VC or PP changes VBUS:** a change of the bits only in step 3 or 4. This is not expected.
- **Above 4.4 V (bit 9) in a step:** an unknown supply. Examine the hardware before more tests.

## Equipment for the owner

- A multimeter is the best item. Measure VBUS to GND on a USB-C breakout board during each step.
- The KWS-2302C meter starts at 4 V. It can only show if VBUS is above 4 V.
- A cable with a power display (for example the Toocki cable) shows only the power of a charge. It cannot measure this.
- Without a meter, the probe log is the measurement.

## Hardware notes for later (no change before the owner decides)

If the test shows that a hardware change is necessary, the next research items are:

- The current that pin 18 can supply (no public value), and the current of the EarPods at 5 V (measure through the dock with the KWS-2302C).
- The minimum voltage of the EarPods (a bench test with an adjustable supply).
- The power loop: the USB-C mod connects VBUS to the charger input of the iPod. If the iPod supplies VBUS itself, the charger and `USBPowerSense` see it as USB power.
- The back-feed: a charger or a computer on the port puts 5 V on VBUS. A direct wire from pin 18 to VBUS puts this 5 V on the 3.3 V rail. Each design needs a diode or a load switch.

## Emulator results

Probe 1.29, trigger '3', 2026-10-17. The instrumented emulator records the I²C writes and a marker at 0x264d78 and 0x2860e8.

| Time (emulated) | Event | I²C write to device 0x10 (PMU address 8) |
|---|---|---|
| 245.3 s | The button press | — |
| 254.80 s | The host start 0x2860e8 | — |
| 254.82 s | 0x264d78 from the UIM init | register 0x25 = 0xf8 (on) |
| 271.37 s | 0x264d78(1): step 2 | register 0x25 = 0x18 (off) |
| 281.58 s | 0x264d78(3): after step 2 | register 0x25 = 0xf8 (on) |

The firmware also calls 0x264d78 at 0.14 s, 2.18 s and 3.40 s after the cold start. Thus the accessory power is a part of the normal start, not only of the Camera Connector.

The log had 71 VBUS records (1 info record, 4 × 10 records and 30 records), as expected. The info record gave the PMU type 3 (PCF50605) and the hardware ID 0x000B0010. PORTSC bit 12 changed only in step 3, and OTGSC bit 1 only in step 4. Step 5 set both, and the probe cleared OTGSC bit 1 at the end. The probe wrote the log, and the main menu operated after the test.

The emulator has no USB controller and no VBUS. Thus OTGSC showed no VBUS in each step, and this result says nothing about the real hardware.

## Real iPod results

Probe 1.29, trigger '3', 2026-10-17. No cable on the iPod at the start. The owner connected the USB-C EarPods directly in step 5. PMU type 3 (PCF50605), hardware ID 0x000B0011.

| Moment | OTGSC | PORTSC | Meaning |
|---|---|---|---|
| Before the host start (device task) | 0x00080000 | — | No comparator bit set: VBUS below approximately 0.2–0.8 V |
| Step 1: Apple's host mode state (pin 18 on) | 0x003F1E00 / 0x003F3E00 | 0x21001000 | Bit 12 (B-session end) set: VBUS below approximately 0.8 V |
| Step 2: pin 18 off | the same | 0x21001000 | No change |
| Step 3: PP off | the same | 0x21000000 | No change |
| Step 4: VBUS charge on | 0x003F0E02 / 0x003F2E02 after 1 s | 0x21001000 | Bit 12 clear: VBUS above approximately 0.8 V (the weak charge resistor, no load) |
| Step 5: all on, the EarPods connected | 0x003F0E02 / 0x003F2E02 | 0x21001000 | No port connection, no tone |

The GPIOL bit 0x10 (the USB power pin) was low in all steps. Bit 13 (0x2000) is the 1 ms toggle of the controller.

**Caution for the log:** in host mode the controller holds OTGSC bits 9–11 on. The log showed "VBUS valid" (above 4.4 V) and "B-session end" (below 0.8 V) at the same time, which is not possible. In host mode, only bit 12 measures VBUS. The log decoder of the branch uses bit 12 first now.

Conclusions:

1. With the 3.3 V accessory power on, VBUS stays below approximately 0.8 V. Thus **the USB-C mod does not connect dock pin 18 to VBUS**.
2. PP (PORTSC bit 12) drives no supply on the iPod.
3. VBUS charge (OTGSC bit 1) lifts the open VBUS line above approximately 0.8 V, but it cannot supply a device. The EarPods did not connect.
4. **Gate result: fail.** The iPod cannot power USB-C headphones without a hardware change. The owner decides on a hardware change. The research items for it are in "Hardware notes for later".
