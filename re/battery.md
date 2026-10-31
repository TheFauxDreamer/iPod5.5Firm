# The battery gauge in RetailOS 1.3

Status (31 October 2026): research only. There is no patch. This note records how the firmware 1.3 of the iPod Video calculates the battery level. The section [The battery number](#the-battery-number-31-october-2026) records the research for a battery percentage.

The owner asked a question: "I have a larger battery, and the battery symbol never changes. How does the iPod calibrate the battery?"

## The answer

- The firmware does not calibrate the battery. It does not know the capacity, and it does not count the charge.
- The firmware measures the battery voltage with the ADC of the PMU. It compares the value with a fixed table of 15 limits. The table gives a level from 0 to 15.
- Thus a larger battery of the same type gives the same icon steps. Each step lasts longer.
- An icon that never changes has a different cause. Refer to [Probable causes of an icon that does not change](#probable-causes-of-an-icon-that-does-not-change).

## The method

- Ghidra project `osos13` with the scripts in `re/ghidra-scripts/` (`FindConstant`, `DecompileAt`, `CallerTree`, `ListVtable`).
- The instrumented emulator with `IPODFW_MARK_AT=0x264ee8,0x1dfe44,0x28341c` and `IPODFW_REGS_AT=0x264ee8,8`. The test used a copy of the drive of the app emulator profile.
- The emulator source: `tools/ipod-machine/src/hw/pmu.rs` and `research/09-what-the-hardware-must-supply.md`.

## The path from the ADC to the icon

| Step | Address | Function | Evidence |
|---|---|---|---|
| 1 | 0x282f58, 0x282d90, 0x282e30 | I²C primitives. 0x282f58 writes 1–4 bytes to an I²C address. 0x282d90 reads 1–4 bytes. 0x282e30 reads one register. They use the controller at 0x7000C000. | Static |
| 2 | 0x283634, 0x283540 | PMU write and PMU read. They use I²C address 8 (the PCF50605). Arguments: (register, count, data). | Static, Emulator (`pmu` census) |
| 3 | 0x283704 | PMU type. Reads PMU register 0. The value `$` (0x24) gives type 2. Other values give type 3. The type selects the ADC registers. | Static |
| 4 | 0x28341c | ADC conversion (channel, mode, out). Type 3: writes ADCC1 (0x2e) and ADCC2 (0x2f) = channel << 1 \| 1. Reads ADCS1/ADCS2 (0x30) until bit 15 (ready) is set. The 10-bit result is ADCS1 << 2 \| (ADCS2 & 3). Type 2 uses 0x30 and 0x32. | Static, Emulator |
| 5 | 0x265f74 | Battery ADC read: 0x28341c(3, 0, out). Channel 3 is `ADCIN1_SUBTR`. | Static, Emulator (0x2f = 0x07, 1540 writes) |
| 6 | 0x265fd8 | Calls 0x265f74 again if it fails. After a failure, it resets the I²C controller (0x282f0c). | Static |
| 7 | 0x265fb4 → 0x264ee8 | Changes the ADC value into a level 0–15 with a table. | Static, Emulator (r0 = ADC value) |
| 8 | 0x9b24c | Returns level × 256 / 15 (0–256). It returns 0x101 if the read fails. | Static |
| 9 | 0x1dfe44 | Power controller method +0xd0 (vtable slot 0x6707f0). Returns the icon value 0–20 and keeps it at 0x10822eac + 0xc. | Static, Emulator |
| — | 0x1dff54 → 0x9b284 | Power controller method +0xd4. Returns the raw ADC value, or −1 after a failure. | Static |

### The channel

The PCF50605 mux has these channels (from Rockbox `pcf5060x.h`, copied in the emulator research):

| Mux value | Name | Use |
|---|---|---|
| 0x0 | `BATVOLT_RES` | Not the battery on the iPod. |
| 0x2 | `ADCIN1_RES` | The battery for Rockbox, resistive divider. Rockbox: mV = ADC × 6000 / 1024. |
| 0x3 | `ADCIN1_SUBTR` | The battery for RetailOS. The same input, in subtractor mode. |
| 0x4 | `BATTEMP` | Battery temperature. |

Subtractor mode removes an offset and gives a different scale. The scale in millivolts is not known. It needs the PCF50605 data sheet or a measurement on a real iPod. Thus this note gives ADC values, not millivolts.

### The tables

0x264ee8 selects a table from the hardware revision. 0x265164 returns the revision word (RAM 0x1081de40 + 0x28). The function uses the word >> 16. The six tables are in RAM at 0x1081de98–0x1081df4b. The start code copies them from osos 0x69c13c.

The level is the count of table values that are not larger than the ADC value. A value below the first limit gives level 0. A value at or above the last limit gives level 15.

| Revision (word >> 16) | RAM | osos | The 15 limits (ADC values) |
|---|---|---|---|
| 4, 5 | 0x1081de98 | 0x69c13c | 282 287 305 315 319 324 331 341 351 367 388 400 423 450 472 |
| 6, 8, 10, other | 0x1081deb6 | 0x69c15a | 275 286 302 312 316 321 327 334 342 354 373 389 404 419 445 |
| 7 | 0x1081ded4 | 0x69c178 | 287 292 312 322 325 329 335 343 358 376 393 407 422 456 475 |
| 9 | 0x1081def2 | 0x69c196 | 291 303 314 321 324 328 332 339 348 363 379 391 405 414 440 |
| 0xb | 0x1081df10 | 0x69c1b4 | 283 302 311 317 319 325 330 338 350 365 382 395 404 436 454 |
| 0xc | 0x1081df2e | 0x69c1d2 | 277 295 306 315 320 325 331 340 353 368 382 397 415 434 456 |

Evidence: Static (0x264ee8 and its literal pool 0x264f8c–0x264fa0). Emulator: the 180 bytes at 0x1081de98 are the same as osos 0x69c13c–0x69c1ef after the start.

The emulator gives the revision word 0xb0010 (revision 0xb). The revision of the real iPod of the owner is not known.

### From the level to the icon value

0x9b24c gives level × 256 / 15. 0x1dfe44 multiplies by 20 and divides by 256. The integer results are:

| Level | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Icon value (0–20) | 0 | 1 | 2 | 3 | 5 | 6 | 7 | 9 | 10 | 11 | 13 | 14 | 15 | 17 | 18 | 20 |

0x1ae774 selects the battery picture from the icon value. Refer to [The battery number](#the-battery-number-31-october-2026).

### The rules in 0x1dfe44

The function has two arguments: the power controller and a mode word.

1. 0x9c258 tests a power state (0x2654a0 gives 1). This is probably "the charger is connected".
2. Without the charger, the function reads the ADC at each call. It sets the counter at +0x10 to 0.
3. With the charger, the function does not read the ADC for the first six calls. It increases the counter at +0x10. After six calls, it reads at each call.
4. If the read fails (0x9b24c returns 0x101), the function does not change the stored value. It returns the old value.
5. Without the charger and with mode 0, the value can fall by only one step at each call. The value can rise at once. The stored value 0x15 (21) means "no value yet". It disables this rule.
6. If the byte at 0x1081dffb is not 0, the function returns 5. The file `_battery_always_low` sets this byte. Refer to [device-switches.md](device-switches.md).

Evidence: Static. Emulator: the stored value at 0x10822eb8 (0x10822eac + 0xc) is 0x14 (20) after the start.

### How often the firmware reads the battery

The emulator ran for approximately 260 seconds on the main menu. The markers at 0x1dfe44 and 0x264ee8 came in groups of five calls, with 30.0 seconds between the groups. Each call to 0x1dfe44 made one call to 0x264ee8. The register record gave r0 = 0x200 (512) at 0x264ee8 at each call. The caller was 0x265fd4.

The emulator answers channel 3 with a fixed value, 0x200. This value is above the last limit of each table. Thus the emulator always shows a full battery. To test other values, the emulator needs a change. The current `ipod-emulator` sets only channel 2 from the battery of the Mac.

## Other users of the battery ADC

| Address | Function | Evidence |
|---|---|---|
| 0x264cb0 | Battery test before the drive starts (called from 0x265cc8 at 0x265d30). The raw ADC value must be at or above a limit: 0x115 (277) or 0x12a (298), or 0x55 (85) or 0x80 (128) if 0x265194 returns 1. Revisions 5, 6 and 9 use the lower value of each pair. | Static |
| 0x1f5e68 | iAP battery report to an accessory. Sends a byte 0–255 from 0x9b24c. A value above 75 (0x4b) gives the "not low" flag. | Static |
| 0x265abc | ADC channel 5, twice. Probably the accessory identification resistor. Not the battery. | Static |
| 0x266034 | ADC channel 7 or 4. Not the battery. | Static |

The emulator research found that the boot loader also reads channel 3 when no charger is connected. It continues only if the value is at least 0x080.

## Probable causes of an icon that does not change

The firmware has no capacity value. Thus a larger battery alone does not stop the icon. These causes are possible. None is tested on the real iPod.

1. **The voltage stays above the last limit.** Level 15 starts at the last value of the table (440–475). Some replacement batteries have a higher full voltage (for example 4.35 V cells). Such a battery stays at level 15 for a longer time. It then falls quickly near the end. The scale in millivolts is not known, so this note cannot give the voltage of the last limit.
2. **The ADC read fails.** Then 0x1dfe44 keeps the old value at each call (rule 4). The icon does not change. A bad battery connector or a damaged flex cable can cause this.
3. **The charger state is wrong.** If 0x9c258 reports a charger, the firmware uses the charge path.
4. **The byte at 0x1081dffb is set.** Then the icon value is always 5. This occurs only if `iPod_Control/Device/_enable_options` and `_battery_always_low` are on the iPod.

To find the cause on the real iPod, read the raw ADC value. The Apple Diagnostics mode probably shows battery values. This is not tested. A future debug patch can also show the result of method +0xd4 (0x1dff54).

## A possible patch (proposal only)

A patch can replace the 15 limits of one table. The tables are in RAM, so a patch must write them after the start copy, or change the source at osos 0x69c13c. A patch is not useful before the real ADC values of a full and an empty battery are known. Do not make this patch now.

## Open questions

- The scale of channel 3 (`ADCIN1_SUBTR`) in millivolts.
- The hardware revision of the real iPod of the owner. The notes for 0x265164 in `docs/firmware-functions.md` give 0xb0005 on a 5G and 0xb0011 on a retail 5.5G. Thus the word >> 16 is 0xb, and the table is probably the 0xb table at osos 0x69c1b4. Confirm this on the real iPod.
- The meaning of the mode word of 0x1dfe44. 0x12ed80 gives 0x660c.
- The meaning of 0x2654a0 and 0x265194 (probably the charger state and the power source).

## The battery number (31 October 2026)

The firmware 1.3 has a hidden numeric battery display. It shows the raw ADC value in place of the battery picture. Apple left the display in the firmware, and an empty file on the iPod switches it on. A patch can use the same display for a percentage.

### Evidence

| Item | Result | Evidence |
|---|---|---|
| View 25599 (element 0x63ff) | The battery view: top 5, width 27, height 13, right margin 6. It is element 5 of the title bar View 24506. Views 22401 and 22157 also have it. It has 28 elements: pictures of 27 × 13 and, at index 27, a text. | Static (View dump) |
| Text element at index 27 | `Str`, element ID 0x63fc, data group 0x6380, text style Type 24223 (0x5e9f). | Static (View dump) |
| 0x1ae774 | Selects the element of the battery view. Value + 4 selects a picture for the value 0–20. If 0x1ebfec returns not 0, it selects 0x1b (27): the text. | Static |
| 0x1ae660 | Gives the index to each battery view. A view with the bit 0x1000000 at + 0x20 uses a different index. The View records of 25599 do not have this bit in their flags. | Static |
| 0x1ebfec | Reads the byte at 0x1081dfe3. If it is not 0, it marks the element `Str` 0x63fc for a new draw. | Static |
| 0x1e804c, case 0x63fc | Calls method + 0xd4 of the power controller (0x1dff54, the raw ADC value). Writes it as text with 0x11e6e8 and the format `%ld` at 0x1e8c54. | Static |
| 0x1e804c, case 0x63fd | Gives the icon value with 0x1e7fe4, with the limits 0 and 20. | Static |
| 0x1ed730 | Marks all the status elements for a new draw (0x63fe, 0x63ff, 0x6400, 0x63fd, 0x5e0b, 0x5e0a), and also 0x63fc through 0x1ebfec. | Static |
| 0x1ecc8c | The first test in 0x1ae774. If it returns not 0, the function does not read the flag, and it selects the pictures 0–3, 0x19 and 0x1a. This is probably the path with the charger. Thus the number probably does not show during a charge. | Static. The meaning is not confirmed. |
| 0x1081dfe3 | Set by the file `_show_voltage`. Refer to [device-switches.md](device-switches.md). The start value at osos 0x69c287 is 0. 0x1d3610 clears the switch bytes at each read, so a change of the start value does not stay. | Static |

This answers one earlier open question: the code that selects the battery picture is 0x1ae774.

### A test without a firmware change

The test is safe because it adds only 2 empty files. Delete the files to stop the test.

1. Connect the iPod in disk mode.
2. In `iPod_Control/Device/`, make an empty file with the name `_enable_options`.
3. In the same folder, make an empty file with the name `_show_voltage`.
4. Eject the iPod.
5. Restart the iPod with Menu + Select.
6. Disconnect the charger and look at the top right of the screen.

Expected result: a number replaces the battery picture. The revision 0xb table gives approximately 283 (empty) to 454 (full).

Real iPod test (31 October 2026, owner, 1 TB iPod with HFS+): the display showed "43" in place of the battery picture. Thus the 2 files and the hidden display operate on a real iPod.

The owner reports (31 October 2026): the battery is almost full, "43" is complete and clear with no cut digit, and a restart showed "43" again.

The value is not explained yet. Static: method + 0xd4 is 0x1dff54 → 0x9b284 → 0x265fd8 → 0x28341c(3, 0, out), and the text is `%ld` of that value. No step divides it. A true value of 43 is below the first limit of each table, and below the boot limit 0x080, so the icon would show empty. The owner's iPod is almost full. Thus the display possibly drops a complete third digit that does not fit, which gives 430–439. This agrees with an almost full battery (level 13 of the 0xb table starts at 436). 0x2438bc does not prove this: the part that was read does not show a drop of a character. The element flags (0x1000208) has the bit 0x1000000 (centre) and not 0x8000000. Other explanations are not excluded.

### What the test gives

- The width: if the number fits in 27 pixels, "100%" possibly also fits.
- The real ADC values for a full and an empty battery. These values also show the scale.
- The cause of the battery icon that does not change. If the number stays above the last limit for a long time, cause 1 is correct.

### The 3 display options

The owner does not want a percentage that always replaces the icon. A patch must give 3 options:

| Option | What shows | Method |
|---|---|---|
| Icon | The Apple icon | The patch does not set the switch. No change from Apple firmware. |
| Icon + Percent | The icon and the percentage beside it | The patch shows 2 children of the battery view. |
| Percent | Only the percentage | The patch sets the switch and changes the text. |

The test with the 2 files is only a measurement. It replaces the icon for the test. It is not the final design.

A row in Settings gives the 3 values. Use `settings_items`, as `up-next` does for Hold Select. The app gives the default with `options`. Refer to [../docs/patch-system.md](../docs/patch-system.md).

During a charge, all 3 options show the charge icon and no percentage. The voltage is too high during a charge, so the value is wrong.

### Hooks (Static, Ghidra `DumpCode`)

| Hook | Word | Function |
|---|---|---|
| `bl` at 0x1e8af8 | `adr r1, 0x1e8c54` (e28f1f55) | Runs only in case 0x63fc. The earlier instruction puts the raw value in r2. The hook changes r2 to the percentage and sets r1 to `%ld%%`. The next instruction sets r0 again, so the hook can change r0. If r2 is −1, the read failed: keep the last percentage. The method 0x1dff54 does not change. |
| `bl` at 0xb4abc | `bl 0x1d3ac4` | The hook calls 0x1d3ac4, then sets 0x1081dfe3. 0x1d3610 clears this byte at each read, thus the hook must run after the call. A change in Settings writes the byte directly. |
| `bl` at 0x1ae6b8 | `bl 0x1ae6d0` | The only call of 0x1ae6d0 (view, index). That function makes one child visible with method + 0x9c. For Icon + Percent, the hook makes the icon child visible and also child 27. It gets the icon value with 0x1e7fe4. |

Percent needs the first 2 hooks. Icon + Percent needs all 3. The firmware draws the text, so the patch does not need its own draw code. With the switch on, 0x1ed730 marks the text for a new draw.

### Text style (Static)

0x21a168 reads a Type record:

| Offset | Content |
|---|---|
| +0x00 | u16: the `Str` ID of the font family list |
| +0x04 | Size. The value 0 gives 6. |
| +0x08 | Colour: R, G, B, A |
| +0x0c, +0x0d | Style bytes. +0x0d goes to the view. |

| Type | Font (`Str` ID) | Size |
|---|---|---|
| 24223 (the battery text) | Podium Sans (0x5e3c) | 18 |
| 24197, 13719 | Espy Sans (0x5e36) | 10 |
| 24170 | Pixo (0x5e2f) | 7 |

The battery text box has a height of 13. Size 18 is probably too large, so the hidden number can be cut in the test. Report the visible digits if this occurs.

The percentage needs size 10. A patch can change the style live: 0x243fb0 (label, parent, Type ID) calls 0x21a168 with the gc at label + 0x74. Static only.

### Space for Icon + Percent

- The icon is at x = 287–313. The title of View -285 ends at x = 280 (inset 40 at each side). Thus 6 pixels are free.
- Size 10 needs approximately 24 pixels. This is an estimate.
- The hook widens the battery view to the left by 30 pixels, and sets the rectangles of the 2 children (child + 0x58: top, left, bottom, right).
- A centred title of up to 186 pixels does not touch the text. For a longer title, set the inset to 72 at each side, only with this option.
- Views 22401 and 22157 have the same battery view. They need the same rectangles.

### The percentage

1. Use a line between the 15 limits of the table, not level × 100 / 15. The level alone gives steps of 6.7 %.
2. Filter the value. Without a charger, let the value only fall, as rule 5 of 0x1dfe44 does.

The percentage is an estimate, because it comes from the voltage. A load lowers the voltage for a short time.

For a larger battery of the same voltage, the voltage curve is similar. If a battery has a higher full voltage, the value stays at 100 % for a longer time. Then the app needs a setting for the full value and the empty value. Use the real test values to decide this.

### Open questions

1. Does the dark theme have a white version of a size 10 style? If not, the patch needs one.
2. Does a script read 0x1081dfe3 through 0x1d3780? The effect is not checked.
3. Does a live rectangle stay after a new layout? Only the emulator can show this. If not, use the start method of `dark-mode`: the option then needs a restart.
4. Does size 10 fit in the box? Only a draw can show this.

### Verdict

| Option | Possible | Risk | Work | Size (estimate) |
|---|---|---|---|---|
| Icon | Yes | None | None | 0 bytes |
| Percent | Probably | Low | Low | 300 bytes |
| Icon + Percent | Probably | Medium: the rectangles and the title | Medium | 500–800 bytes |

Next steps:

1. Do the test with the 2 files. Record the number at full and at empty.
2. Answer the open questions.
3. Make a test patch `battery-display` on its own branch. Make Percent first, then Icon + Percent.
