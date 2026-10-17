# USB-C power mod: power USB-C headphones from the iPod 5.5G

This document is a hardware design for a person who builds iPod mods. With the mod, an iPod 5.5G (iPod Video) with a USB-C port supplies 5 V to USB-C headphones, for example the Apple USB-C EarPods. Then the headphones operate without a powered dock or a charger. The document has no links to other files of the project, so you can share it alone.

**Status: a design only. Nobody has built or tested this circuit.** Each value comes from a datasheet or from a measurement on one real iPod (2026-10-17). Do the bench test (section 9) before you install the board.

## 1. Safety

WARNING: Disconnect the battery before you solder in the iPod. A short circuit of the battery can cause a fire.

WARNING: Never connect the 3.3 V of dock pin 18 directly to the USB-C VBUS. A charger or a computer puts 5 V on VBUS. A direct wire puts this 5 V on the 3.3 V supply of the iPod and can damage the iPod.

CAUTION: Never connect the boost converter output to dock pin 23 (the USB power input of the iPod). The iPod then charges its battery from its own battery. The current can be more than the converter can supply.

CAUTION: The design changes the USB-C port of the iPod. Make sure that the iPod still charges and still connects to a computer before you close the case (section 10).

## 2. The problem

USB-C headphones are USB devices. A USB host must supply 5 V on VBUS to them. The iPod 5.5G has no 5 V output:

- The iPod has a 3.3 V accessory supply on dock pin 18. The firmware switches it through the power management chip (PCF50605, register 0x25: 0xf8 = on at 3.3 V, 0x18 = off). Rockbox uses the same values.
- The Apple iPod Camera Connector changed this 3.3 V to 5 V with its own step-up converter.
- The usual USB-C mods connect the USB-C VBUS only to dock pin 23, the USB power input. They do not connect pin 18.

A test on a real iPod with a USB-C mod (2026-10-17) proved this:

- With the 3.3 V on, VBUS stayed below approximately 0.8 V.
- The "port power" bit and the "VBUS charge" bit of the USB controller supply no usable power.
- The USB-C EarPods did not connect when they were connected directly to the iPod.

Thus the iPod needs added hardware: a 5 V boost converter and USB-C role logic.

## 3. What the mod does

The mod makes the USB-C port a dual-role port (DRP). The port is a power sink to a charger or a computer, as it is now. It is a power source to a USB-C device, for example headphones.

| Situation | Pin 18 | Role of the port | VBUS comes from | iPod USB power input (pin 23) |
|---|---|---|---|---|
| iPod off or asleep, charger connected | 0 V | Sink (Rd on CC with no power) | The charger | Connected: the iPod charges |
| iPod awake, charger, computer or powered dock connected | 3.3 V | Sink | The charger, computer or dock | Connected: charge and sync as now |
| Host mode (USB-C Audio on), USB-C headphones connected directly | 3.3 V | Source | The boost converter in the iPod | Disconnected |
| Nothing connected | 0 V or 3.3 V | No connection | Nothing | — |

The role logic is the USB Type-C standard method. The port controller looks at the CC pins of the connector:

- A charger, a computer or a dock pulls CC up (Rp). The controller then acts as a sink.
- Headphones pull CC down (Rd). The controller then acts as a source and turns on VBUS.

The USB-C standard requires this logic: a source must not put 5 V on VBUS before it detects a sink. Thus a simple "always on" 5 V output is not correct. It can also push current into a charger.

## 4. Block diagram

```
 USB-C connector                                           iPod side
 ---------------                                           ---------
                         +-----------------------+
 VBUS ---+---------------| U4 load switch        |-------- dock pin 23 (USB power input)
         |               | VIN    TPS22918   VOUT|
         |               |          ON           |
         |               +-----------+-----------+
         |                           |
         +-- R4 100k --+-------------+
         |             |             |
         |          R5 220k       Q1 drain     (Q1 on = U4 off)
         |             |          Q1 source
         |            GND            |
         |                          GND        Q1 gate <-- BOOST_EN
         |
         +-- R1 887k ------------------ U1 VBUS_DET
         |
         +---------------------------- U3 VOUT   (5 V boost)
                                       U3 VIN  <-- F1 <-- battery +
                                       U3 EN   <-- BOOST_EN

 CC1 --------------------------------- U1 CC1   (port controller TUSB320LAI)
 CC2 --------------------------------- U1 CC2
                                       U1 VDD  <-- dock pin 18 (3.3 V)
                                       U1 ID ---+-- R2 200k -- dock pin 18
                                                |
                                                +-- U2 inverter --+-- BOOST_EN
                                                    (VCC = pin 18) |
                                                                   +-- R3 100k -- GND

 D+, D- ------------------------------ no change (dock pins 27 and 25)
 GND --------------------------------- iPod GND (dock pins 15 and 16) and battery -
```

## 5. How the circuit operates

1. U1 (TUSB320LAI) is the USB-C port controller. It gets its power from dock pin 18.
2. When U1 has no power, its CC pins have 5.1 kΩ pull-down resistors ("dead battery" mode). The port is then a plain sink, as the mod is now. Thus a charger always charges the iPod when it is off or asleep.
3. When U1 has power, it operates as a DRP. When it detects headphones (Rd on CC), it pulls its ID pin low.
4. U2 inverts ID. Its output BOOST_EN goes high.
5. BOOST_EN turns on U3 (TPS61240). U3 supplies 5 V to the USB-C VBUS.
6. BOOST_EN also turns on Q1. Q1 pulls the ON pin of U4 low, and U4 disconnects pin 23 from VBUS. Thus the iPod does not charge from its own boost converter.
7. When a charger or a computer is connected, U1 acts as a sink. ID stays high, and BOOST_EN stays low. The voltage divider R4/R5 turns on U4. VBUS then goes to pin 23, as before the mod.
8. When U3 is off, its output has a high impedance ("load disconnect"). Thus a charger on VBUS cannot push current into U3.

## 6. Parts

| Ref | Part | Value or type | Package | Notes |
|---|---|---|---|---|
| U1 | TI TUSB320LAIRWBR | USB-C port controller, DRP, GPIO mode | X2QFN-12, 1.6 × 1.6 mm | VDD 2.7–5 V. Use the TUSB320**LAI**. The older TUSB320 (no suffix) needs I²C commands after dead-battery mode, which this design cannot send. |
| U2 | TI SN74LVC1G04DCKR | Inverter | SC-70-5 | VCC 1.65–5.5 V. Its inputs accept a voltage when VCC is 0 V. |
| U3 | TI TPS61240DRVR | Boost converter, fixed 5.0 V | WSON-6, 2 × 2 mm | VIN 2.3–5.5 V. 200 mA guaranteed, up to 450 mA. Load disconnect when off. EN high = on. |
| U4 | TI TPS22918DBVR | Load switch, 2 A, 52 mΩ | SOT-23-6 | VIN 1–5.5 V. ON high = on. Leave QOD and CT open. |
| Q1 | 2N7002 or DMG1012T | N-channel MOSFET, logic level | SOT-23 or SOT-523 | Gate driven at 3.3 V. |
| L1 | 1.0 µH | Inductor, at least 900 mA saturation | 0805 | For example TOKO MDT2012-CH1R0AN (the TI example). |
| C1 | 2.2 µF | X5R, 6.3 V or more | 0402 or 0603 | U3 input |
| C2 | 4.7 µF | X5R, 10 V | 0603 | U3 output. The total capacitance on VBUS must not be more than 20 µF (the TPS61240 limit). Count the capacitor on the USB-C board. |
| C3 | 100 nF | X7R | 0402 | U1 VDD |
| C4 | 100 nF | X7R | 0402 | U2 VCC |
| C5 | 1 µF | X5R, 10 V | 0402 | U4 VIN |
| R1 | 887 kΩ | 1 % | 0402 | VBUS to U1 VBUS_DET. The datasheet range is 855–920 kΩ. 900 kΩ 1 % is also correct. |
| R2 | 200 kΩ | 5 % | 0402 | ID pull-up to pin 18 (not to another supply) |
| R3 | 100 kΩ | 5 % | 0402 | BOOST_EN pull-down |
| R4 | 100 kΩ | 5 % | 0402 | VBUS to U4 ON |
| R5 | 220 kΩ | 5 % | 0402 | U4 ON to GND. At 5.0 V, ON is 3.4 V. At 4.4 V, ON is 3.0 V. |
| F1 | 500 mA | PTC fuse or fast fuse | 0603 | In the battery + wire to U3 |

Connections of U1 that are not in the diagram:

- PORT: not connected (DRP mode).
- ADDR: not connected (GPIO mode, no I²C).
- EN_N: to GND (always on when VDD is present).
- OUT1, OUT2, OUT3: not connected.

CAUTION: The X2QFN-12 package of U1 has no leads. Use hot air or reflow, and a small PCB. Hand soldering with an iron is not possible.

## 7. The connection points in the iPod

The positions of the points are different for each USB-C mod board. Identify each point with a multimeter.

| Signal | Where | How to identify it |
|---|---|---|
| USB-C VBUS | The VBUS pad of the USB-C connector on the mod board | Continuity to the VBUS pins of the connector |
| Dock pin 23 (USB power input) | The other end of the wire or trace from the USB-C VBUS | Today it has continuity to the USB-C VBUS. The mod cuts this connection. |
| Dock pin 18 (3.3 V accessory power) | The 30-pin connector pads or the flex of the logic board | 3.3 V to GND while host mode runs (USB-C Audio on) |
| Dock pins 15 and 16 (GND) | The 30-pin connector pads | Continuity to the battery − |
| CC1, CC2 | The CC pins of the USB-C connector | Many mod boards have a 5.1 kΩ resistor from each CC pin to GND |
| Battery + and − | The battery connector on the logic board | 3.0–4.2 V |

Pin numbers of the 30-pin dock connector: 15 and 16 GND, 18 3.3 V accessory power, 23 USB power 5 V, 25 USB D−, 27 USB D+.

Why the boost converter gets its power from the battery, not from pin 18:

- Pin 18 comes from a regulator in the PCF50605. Its maximum current is not published.
- The Apple USB-C to 3.5 mm adapter needs approximately 11 mA, and up to 32 mA at full volume (published measurement at 5 V). Through the boost converter this is up to approximately 60 mA at 3.3 V. Other USB devices can need up to 100 mA or more.
- The battery can supply this current. Pin 18 supplies only U1 and U2 (much less than 1 mA).

## 8. Build procedure

WARNING: Disconnect the battery before you start.

1. Build the circuit of section 4 on a small PCB. Put U3, L1, C1 and C2 near each other.
2. Do the bench test of section 9.
3. Open the iPod. Disconnect the battery.
4. Remove the 5.1 kΩ resistors from CC1 and CC2 of the USB-C board. U1 supplies the CC resistors now.
5. Cut the connection between the USB-C VBUS and dock pin 23.
6. Connect the USB-C VBUS to the VBUS net of the PCB.
7. Connect dock pin 23 to the VOUT pin of U4.
8. Connect CC1 and CC2 of the connector to CC1 and CC2 of U1.
9. Connect dock pin 18 to the 3.3 V net of the PCB.
10. Connect GND.
11. Connect battery + through F1 to the VIN of U3. Use a short wire.
12. Do not change D+ and D−.
13. Insulate the PCB with Kapton tape. On an iPod with a flash storage mod, the space of the old hard disk is a good location.
14. Connect the battery. Do the tests of section 10 before you close the case.

## 9. Bench test before the installation

Use a laboratory supply at 3.7 V for "battery +", and a second supply at 3.3 V for "pin 18". Connect a 1 kΩ resistor to GND at the U4 output, as a load for "pin 23".

| Test | Expected result |
|---|---|
| 3.3 V on, nothing on the USB-C port | VBUS 0 V. ID 3.3 V. BOOST_EN 0 V. |
| 3.3 V on, USB-C headphones (or a 5.1 kΩ resistor from CC1 to GND) | ID 0 V. BOOST_EN 3.3 V. VBUS 4.9–5.1 V. U4 output 0 V. |
| 3.3 V on, a USB-C charger | VBUS 5 V from the charger. ID 3.3 V. BOOST_EN 0 V. U4 output 5 V. |
| 3.3 V off, a USB-C charger | U4 output 5 V (dead battery: U1 shows Rd, the charger turns on). |
| 3.3 V on, a computer (USB-C port) | U4 output 5 V. Data must pass on D+ and D− (no change). |
| 3.3 V on, headphones connected, then the 3.3 V off | VBUS goes to 0 V. |
| Current from the 3.7 V supply with 3.3 V on and nothing connected | Less than approximately 0.1 mA (U3 is off). |

CAUTION: If VBUS has 5 V while ID is high, stop. Examine U2, R3 and the EN connection of U3.

## 10. Tests after the installation

The firmware part needs the iPodFirm app with the patch "USB-C Audio" (usb-audio-out). Do these tests in this sequence:

1. Connect a USB-C charger to the iPod while it is asleep. The iPod must charge.
2. Connect the iPod to a computer. The disk must mount, and a sync must operate.
3. Measure pin 18 with USB-C Audio off and the iPod awake. Write down the voltage (refer to section 11).
4. Set USB-C Audio on. Measure pin 18. Expected: 3.3 V.
5. Connect the USB-C EarPods directly. VBUS must be 4.9–5.1 V, and pin 23 must be 0 V.
6. Play a song. The music must come from the EarPods.
7. Disconnect the EarPods. VBUS must go to 0 V.
8. With USB-C Audio on, connect a charger through a USB-C dock. The iPod must charge, and VBUS must not come from the boost converter.

## 11. Firmware notes

These facts come from the analysis of the Apple firmware 1.3 (osos image addresses).

- The function 0x264d78 switches pin 18: argument 1 = off (register 0x25 = 0x18), argument 3 = on (0xf8), argument 2 = PMU mode 2 (0x58).
- At the start, the firmware writes 0x18 (off) and then 0x58 (mode 2). The meaning of mode 2 is not published. Thus the voltage of pin 18 in normal use is not known. Test 3 of section 10 measures it.
- When host mode starts, the firmware writes 0xf8 (on). Thus pin 18 has 3.3 V in host mode.
- The firmware does not turn pin 18 off when host mode stops.

What this means for the mod:

- If pin 18 is 0 V in normal use (mode 2 = off), the port is a DRP only in host mode. That is the correct behaviour. No firmware change is necessary.
- If pin 18 is 3.3 V in normal use, the port is a DRP also when USB-C Audio is off. Then two items are possible:
  - The iPod supplies power to USB-C headphones also when it does not play to them. This only uses battery power.
  - A computer with a dual-role USB-C port (for example a Mac) can select the wrong role at random. Then the iPod can act as the source, and the sync does not start. Disconnect and connect the cable again.
- In both cases, a small firmware change can make the behaviour exact: call 0x264d78(1) when USB-C Audio is off, and 0x264d78(3) when it is on. Ask the iPodFirm project for this change.
- Direct connection of the EarPods to the iPod (without a hub) is not tested yet. All tests of the USB host mode used a dock with a hub. The firmware supports a device on the root port, but a test is necessary.

## 12. Power and battery life

The boost converter takes this extra current from the battery:

extra current ≈ 5 V × device current ÷ (battery voltage × 0.85)

| Device current at 5 V | Extra battery current at 3.7 V |
|---|---|
| 11 mA (Apple adapter, normal volume) | approximately 17 mA |
| 32 mA (Apple adapter, maximum output) | approximately 51 mA |
| 100 mA (one USB 2.0 unit load) | approximately 160 mA |

The TPS61240 supplies at least 200 mA. The design is for headphones and small USB DACs, not for devices with a high current.

## 13. Open items and risks

- Nobody has built the circuit. Do the bench test first.
- The voltage of pin 18 in normal use (PMU mode 2) is not known (section 11).
- The maximum current of pin 18 is not known. The design uses it only for U1 and U2.
- A partner with a dual-role port (a computer or a phone) can select either role. The TUSB320LAI in GPIO mode cannot be set to prefer the sink role.
- The total capacitance on VBUS must not be more than 20 µF (TPS61240). The USB-C standard asks for more capacitance on a host port. With headphones this is not a problem.
- Each USB-C mod board is different. The positions of CC, VBUS and pin 23 must be found on each board.
- When the iPod sleeps, pin 18 goes off, and the headphones lose power. The iPod sleeps only when the music is paused or stopped. After the iPod wakes, the headphones connect again.

## 14. Sources

- TI TUSB320LAI datasheet (SLLSEQ8D): DRP and GPIO mode, the dead-battery Rd (4.1–6.1 kΩ), ID open drain, VBUS_DET with 887 kΩ (855–920 kΩ). https://www.ti.com/product/TUSB320LAI
- TI TUSB320 datasheet (SLLSEN9F): the I²C step after dead-battery mode, which is the reason to use the LAI version. https://www.ti.com/product/TUSB320
- TI TPS61240 datasheet: 2.3–5.5 V in, 5.0 V out, 200 mA (up to 450 mA), load disconnect, 1.0 µH, 2.2 µF, 4.7 µF, maximum 20 µF output capacitance. https://www.ti.com/product/TPS61240
- TI TPS22918 datasheet: 1–5.5 V, 2 A, 52 mΩ, ON active high. https://www.ti.com/product/TPS22918
- TI SN74LVC1G04 datasheet. https://www.ti.com/product/SN74LVC1G04
- Rockbox `accessory_supply_set`: PCF50605 register 0x25, 0xf8 on and 0x18 off. https://github.com/Rockbox/rockbox (firmware/target/arm/ipod/powermgmt-ipod-pcf.c)
- Current of the Apple USB-C to 3.5 mm adapter (A2155): 10.9 mA and 32.1 mA. https://reference-audio-analyzer.pro/en/report/amp/apple-usb-c.php
- The VBUS test on the real iPod and the firmware analysis: the iPodFirm project, `re/usb-power.md` on the branch `usb-vbus-test`.
