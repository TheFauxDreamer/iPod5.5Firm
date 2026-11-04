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

Owner report (31 October 2026): since the battery mod (a larger battery), the icon never operated correctly. It looks almost full, and then it goes directly to flat.

This agrees with a value of 430–439: level 13 of the 0xb table starts at 436, and it gives an icon value of 17 from 20. It suggests that the voltage of this battery stays nearly constant for most of the discharge and then falls quickly. This is an estimate. A record of the value over one complete discharge will show the real curve. If the curve is this flat, a percentage from the voltage alone stays near one value for most of the time. Then the patch needs a table from the real curve, or a different method.

Owner report (31 October 2026): during the music test, the display went from "43" to "44". Thus the display follows the value, and a fixed text is excluded. The charger state during the rise is not recorded. A rise without a charger can be a recovery of the voltage after a load, for example after the start.

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
3. Does a live rectangle stay after a new layout? Answer (emulator, 3 November 2026): yes. Refer to [Version 0.4](#version-04-emulator-tests-and-the-text-path-3-november-2026).
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

## The patch `battery-log` (31 October 2026)

The raw logs are in [battery-logs/](battery-logs/).

The test patch records the complete raw value and thus answers the question of the value 43.

0x1d91dc is the UI timer handler that reads the icon value. It calls 0x1e7fe4 at 0x1d91f8 (`bl`, eb003b79), starts the timer at + 0xa0 again and marks the status elements. The emulator showed the battery reads approximately each 30 s. Static: 0x1d91dc has one caller, 0x1d8ebc in 0x1d8e68.

### First log from a real iPod (31 October 2026)

The owner disconnected the power and played music. The patch (version 0.1) wrote 34 samples at 5-minute intervals, for 9964 s (2.77 hours). The first raw value was 433 and the last raw value was 417.

| Measurement | Result |
|---|---|
| Hidden number | The complete raw value is 3 digits. The raw values of 430–438 agree with the display "43". Thus the display of the switch `_show_voltage` drops the third digit. |
| Time between samples | 300 s or 301 s. The log has no gap. The owner did not report the state of the backlight. |
| Fall of the raw value | 7.7 units for each hour (a straight line through all samples). |
| Noise | A sample is up to 4.5 units from the line. The value also rises between samples, for example 417 to 419. |
| Icon value | 18 until 1560 s (raw 435). 17 from 1860 s (raw 432). |
| Charger column | Always 1, with no charger connected. |

Conclusions:

1. The voltage is not flat in this part of the discharge. This does not agree with the estimate in the owner report above. The log does not show the end of the discharge.
2. The change from icon 18 to 17 is at a raw value of 432–435. Limit 434 of the table for revision 0xc and limit 436 of the table for revision 0xb both agree with this. The second log gives the answer: revision 0xb.
3. A percentage needs a filter. One sample has noise of more than one percent of the range.
4. The value of 0x9c258 is not proven to be the charger state. The value 1 with no charger does not agree with "the charger is connected". The log needs a sample with the charger connected for a comparison. Until then, read the fourth column as a power state with an unknown meaning.

A full discharge from a full charge is necessary to give the full value, the empty value and the curve.

### Second log: to the end of the battery (1 November 2026)

The owner played music until the iPod stopped. The patch (version 0.1) wrote 220 samples for 65797 s (18.3 hours). The first raw value was 415, and the raw value was then 423 for 15 minutes. The last raw value was 116. The time between samples was 300–303 s.

The log did not start from a full charge. The owner charged the iPod for 1 hour before the log.

The icon changes agree with the table for revision 0xb. They do not agree with any other table:

| Icon change | Raw value at the change | Limit in the 0xb table |
|---|---|---|
| 17 to 15 | 405 to 403 | 404 |
| 15 to 14 | 396 to 393 | 395 |
| 14 to 13 | 380 | 382 |
| 13 to 11 | 364 to 363 | 365 |
| 11 to 10 | 350 | 350 |
| 10 to 9 | 341 to 337 | 338 |
| 9 to 7 | 329 | 330 |
| 7 to 6 | 326 to 325 | 325 |
| 6 to 5 | 319 to 316 | 319 |
| 5 to 3 | 317 to 314 | 317 |
| 3 to 2 | 312 to 311 | 311 |
| 2 to 1 | 303 to 300 | 302 |
| 1 to 0 | 284 | 283 |

Results:

1. The iPod of the owner uses revision 0xb, as the emulator does.
2. The icon value reached 0 at 43581 s, at raw 284. The iPod then played for 6.2 more hours, and the raw value fell to 116. Thus the Apple table ends far above the end of this larger battery.
3. The raw value falls steadily through the complete log. It has no flat part. This does not agree with the earlier estimate of a nearly constant voltage.
4. The fall is not constant. It is approximately 12 units each hour from 400 to 300, and approximately 26 units each hour from 280 to 130. The last 3 samples fell by 5, 4 and 7 units.
5. The icon value can rise by one step, for example 9 to 10 at 29172 s. This agrees with rule 5 of 0x1dfe44.
6. The fourth column was 1 for all samples. No sample with a charger exists yet.

The owner report of an icon that goes from almost full to flat does not agree with this log. The icon fell in steps for 12 hours. The icon did reach 0 too early. The cause of the report is not proven.

### Play time that remains

This table comes only from the second log. It gives the hours of music that remained at each raw value. The first log is not part of this table, because a charge occurred between the 2 logs.

| Raw value | 415 | 405 | 396 | 380 | 363 | 350 | 337 | 325 | 311 | 300 | 284 | 250 | 200 | 150 | 116 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Hours left | 16.8 | 15.7 | 14.9 | 13.9 | 12.4 | 11.2 | 10.1 | 8.8 | 7.6 | 6.9 | 6.2 | 4.8 | 2.5 | 0.8 | 0 |

The full value and the play time from a full charge are not known. The highest raw value in the 2 logs is 438. The table cannot give a percentage until a log starts from a full charge.

Decisions for the `battery-display` patch:

- Do not use the Apple table for the percentage on this iPod. It gives 0 % with 6.2 hours of play time left.
- Use a table of raw values and percentages, with a line between the points.
- Other batteries need other tables, so the table must be a setting in the app. The Apple table is the default. A battery log can give a measured table.
- Use a filter. One sample has noise of up to 4.5 units.

### Empty log with the iPod connected (2 November 2026)

The owner flashed the patch (version 0.1) and left the iPod connected to the Mac. The log file stayed empty: all 262144 bytes were zero. The volume was mounted on the Mac during the check.

1. The iPod cannot write the log while the Mac has the disk. Both good logs came from an iPod that was not connected.
2. Version 0.1 set a flag after one failed read or write. The flag stopped the log until the next start. Thus a USB session could stop the log after the disconnection.
3. Version 0.2 tries again at the next sample. Only a full file stops the log. If the read of the file fails, the patch does not write, so the old text stays safe.
4. It is not known if the timer 0x1d91dc runs during a USB session. No sample is possible there, so the charger column needs a wall charger.

### Third log: an idle iPod (2 November 2026)

The owner disconnected the iPod and did not play music. Later, the owner connected a power bank for 15 minutes. The log has 1 sample: `60 451 20 1`.

1. The patch wrote the header and the first sample correctly. The sample before the power bank has charger value 1, so it does not give the charger column.
2. The raw value 451 is the highest value in the 3 logs. The earlier highest value was 438.
3. No sample came at 360 s. The probable cause is the sleep of the idle iPod, because the timer 0x1d91dc is a UI timer. This is not proven.
4. 0x1ee8d0 does not sleep if it finds external power. An iPod that is already asleep possibly stays asleep on a power bank. Do the test with music, so that the iPod stays awake.

Next test: find the full value and the charger column.

1. Charge the iPod to full with a charger, not with the Mac.
2. Clear the log.
3. Start the iPod, with the charger connected for 15 minutes.
4. Disconnect the charger and play music for 1 hour.

### Third log: with a wall charger (2 November 2026)

The iPod played music on a wall charger. The file has 3 samples: 1439 s raw 476, 1739 s raw 477 and 2039 s raw 478. The icon value is 20 and the fourth column is 1 in each sample.

- The fourth column is also 1 on a battery, so it does not show the charger. The meaning of 0x9c258 stays not known.
- The raw value on the charger is up to 40 units above the highest value on the battery (438). The full value with no charger is not known yet.

The app showed only the header. The 18 bytes after the header are 0, and the app stops at the first 0 byte. The probable cause: the iPod wrote the first sample, and then the Mac cleared the file with no restart of the iPod. The patch keeps the end of the text in RAM. It then writes at the old position, and the old position is 18 bytes after the header. The missing line "start" agrees with this.

Fix (patch 0.3): each sample reads the header. If the header is missing, the text starts again after the header position, with the line "start". The app also ignores zero bytes in the file.

### Battery log 0.3 on a real iPod (3 November 2026)

The owner charged the iPod and played music overnight. The file stayed blank. The owner then played music for approximately 7 minutes. The file then had the line "start", 60 s raw 456 and 360 s raw 451, with icon value 20.

- Version 0.3 writes correctly after a clear. The format of the file is correct.
- The iPod does not change the file date when it writes. The date of the log file is not evidence of a write.
- The overnight run with the charger wrote nothing. The cause is not known. The log of 2 November wrote on a wall charger, but its samples started late and its times do not follow the 300 s steps from 60 s.
- The values 456 and 451 are above the highest earlier value on a battery (438). They are the first values after a long charge.

## The patch `battery-display` (1 November 2026)

The options are in the Patches pane, as the owner asked. There is no row in iPod Settings.

Static results from `DumpCode` and `DecompileAt`:

- 0x1ae838 is the `bl 0x1e7fe4` (mode 0) for the battery picture. Hook only this call. Other callers keep the Apple value.
- The object in r5 at 0x1e8af8 is the provider for 0x1e7fe4, because the next case calls 0x1e7fe4 with r5.
- 0x243fb0 uses the Type ID only if the second argument is a provider. The patch gives `str_table` (0x21f3b8).
- The patch gives the text with the format `%s`. Thus it does not need `%%` in the firmware `sprintf`.
- Icon + Percent uses the switch, so that the firmware marks the text. The hook then also shows the icon child. It widens the view by 30 pixels and moves the children (child + 0x58).

The provisional table of the patch uses 20.3 hours from raw 438. This is an estimate. The hours from raw 423 are measured, and the 2 hours above raw 423 use the fall in the first log.

Not tested: the text colour with the dark theme, the text width, and if the rectangles stay after a new layout.

Version 0.2 adds the option Smoothing (off by default) and the import of a battery log. The address list of the tables comes from [The tables](#the-tables). The hardware word comes from 0x265164. The owner's iPod has revision 0xb. The other revisions are not tested.

Version 0.3 shows the percentage during a charge. The charge path of 0x1ae774 gives a child that is not the text child, and `hook_show` then also shows the text. In Percent mode, the view goes back to the normal width after the charge. The size of the error during a charge is not known, because no log sample has a charger. This replaces the earlier design with no percentage during a charge.

### Version 0.4: emulator tests and the text path (3 November 2026)

Emulator tests by the owner, with version 0.3 and Icon + Percent:

- The text was on the icon, and only "10" of "100%" showed.
- After several seconds, the icon and the text disappeared.
- The text was white in Light.

A diagnostic copy of the patch recorded the rectangles at each call of `hook_show` (instrumented emulator, `peek`). The results:

- The rectangles at + 0x58 are screen positions, not positions in the parent. The battery view and its children were all at x = 287–314.
- Version 0.3 put the text at x = 0–30 and moved the icon to x = 317–344, outside the screen. This caused the disappearance.
- 0x1ae6d0 runs approximately 45 times each second, for several battery views.
- A wider view rectangle stays. The firmware does not set it again. This answers open question 3.

The text path (static, Ghidra):

| Address | Fact |
|---|---|
| 0x170954 | Registers the class 0x1580 with the constructor 0x243850. Word 1 of a View element is the class ID. |
| 0x243850 | Allocates 444 bytes and calls 0x244a30. 0x244a30 sets the vtable 0x677920. The draw method (vtable + 0xf4) is 0x244924. |
| View 25599, element 27 | `Str ` 25596: class 0x1580, word 6 = 0x1000208, word 23 = 0. |
| 0x21af84 | The base constructor. Label + 0x20 = element word 6. |
| 0x243f60, 0x243de0 | Label + 0xc8 = the Type record (24223). Label + 0xc0 = element word 23. |
| 0x244924 | Reads the colour from the Type record at each draw. Calls 0x2438bc with label + 0xc0 as the flags. |
| 0x2438bc | If label + 0x20 has bit 0x8 and label + 0xc0 does not have bit 0x200, it uses the colour at RAM 0x10823394, not the Type colour. The battery text has bit 0x8. |
| 0x2438bc, 0x21093c, 0x210744 | 0xe1d38 counts the characters that fit in the box. 0x210744 draws only these characters. |
| 0x1ae820 | `bl 0x1ebfec` with the provider in r5. It runs before each show, except during a charge. |

The other reads of label + 0xc0 in the label code (0x244090, 0x244170, 0x2447c8, 0x24484c) test the bits 0x20, 0x80, 0x10 and 0x40. Only 0x2438bc reads the bit 0x200.

Thus:

- The white text came from the fixed colour. The patch sets the bit 0x200 in label + 0xc0. Then the Type colour applies.
- The "%" was cut because the box was too small. In Podium Sans 14, "100" is 21 pixels wide (measured in an emulator screenshot at scale 2.0). The text box is now 38 pixels.
- Espy Sans 10 also gave white text and no "%". The font was not the cause.
- At the start, the first show came before the first text request. Thus the patch had no provider, and it used the layout for the text alone. The hook at 0x1ae820 now records the provider.

Version 0.4 changes:

| Item | Version 0.3 | Version 0.4 |
|---|---|---|
| Rectangles | Changed relative to the current value | Absolute: the stock values + an offset, for each view |
| Icon | Moved 30 pixels to the right | Does not move |
| Text box | 28 pixels | 38 pixels, right aligned, 1 pixel higher than the icon box |
| Percent mode | The stock box (27 pixels) | A 38-pixel box that ends at the right edge of the stock box |
| Font | Type 24197 (Espy Sans 10) | An own Type record: Podium Sans 14, with the colour of Type 24223 |
| Colour | Fixed colour | The colour of Type 24223: black in Light, white in Dark Gray |
| Start | The text moved after a few seconds | The icon shows until the first valid percentage. Then the text shows |
| Hooks | 4 | 5 (0x1ae820 added) |

Emulator results with version 0.4 (owner, 3 November 2026, firmware from the Python tools, with a test copy that always shows 7 %):

- Light: "100%" and "7%" are black and complete, at the left of the icon.
- Dark Gray: "7%" is white.
- At the start, only the icon shows. Then the text shows, and it does not move.

Not tested: Percent mode, Now Playing, the hold icon, a long title, the charge view, the Swift build path, and a real iPod.

In the Dark Gray build, the rows that are not selected had no arrow. A Dark Gray build with no patch has the same fault, so `battery-display` is not the cause. Refer to [dark-theme.md](dark-theme.md#the-missing-arrows-3-november-2026).

### Version 1.0 (3 November 2026)

The owner decided that `battery-display` is a normal patch, in the category Display. The code is the same as in version 0.4. The letter is now `y`, because `no-now-playing-timer` uses `t` on `main`. The patch `battery-log` stays a test patch.

### Version 1.2 (3 November 2026)

The owner asked for three choices in "Battery Data": Apple, 3000 mAh and Custom.

| Choice | Value | Table |
|---|---|---|
| Apple | 0 | The firmware table, as before |
| 3000 mAh | 2 | `mah3000_raw` and `mah3000_pct`, fixed in the code |
| Custom | 1 | `curve_raw` and `curve_pct`. The app writes the imported curve into them |

Custom keeps the value 1 of the old choice Custom Battery. Thus an iPod with an imported curve keeps its curve. Without an imported curve, Custom has the 3000 mAh values. The measured size is 3684 bytes (version 1.1: 3572 bytes).

The 3000 mAh table comes from the final log and the second log. Refer to [Fifth log](#fifth-log-from-a-full-charge-to-empty-4-november-2026).

#### The method for the final 3000 mAh table

The owner asked to use all logs for the final table. The script [battery-curve-combine.py](battery-curve-combine.py) does this. Each log gives a different part of the data:

| Log | Use |
|---|---|
| The final log, from a full charge until the iPod stops | The top of the curve, the full play time and a curve to empty |
| Second log (1 November), to empty from raw 421 | A second measurement of the hours that remain at each raw value |
| First log (31 October), raw 436 to 417 | A check of the fall rate at the top. It does not change the table |
| Third log (2 November), on a charger | The script shows a caution for a start value above raw 460 |
| Fourth log (3 November), raw 456 to 451 | It shows the fast fall after a charge. The method starts each log at its highest mean value |

The procedure:

1. Add the final log to `battery-logs/`.
2. Run the script. Put the final log first:

   ```
   python3 re/battery-curve-combine.py --empty re/battery-logs/<final log> re/battery-logs/2026-11-01-battery-2-to-empty.txt --check re/battery-logs/2026-10-31-battery-1.txt
   ```

3. Compare the hours that remain at the first common raw value. If the two logs differ by more than 10 %, examine the cause before you use the mean. A different backlight time, EQ or volume can be the cause.
4. Compare the check line of the first log. A large difference shows that the top of the final log is not typical.
5. Put the two lines `MAH3000_RAW` and `MAH3000_PCT` into `battery_display.c`.

The script reads each log with the method of `BatteryCurve.make`. Below the top of the second log, it uses the mean of the hours that remain. Above that value, it keeps the shape of the final log. The 0 % value is the mean of the last raw value of each log.

The script finds the raw value where the hours that remain reach each percentage. `BatteryCurve.make` reads the raw value at equal times. The script must use the raw value, because it combines two logs at the same raw value.

With only the second log, the script gives the values below. The largest difference from `BatteryCurve.make` is 4 raw units (161 in the app, 165 in the script, at 7 %):

```
#define MAH3000_RAW  { 421, 414, 405, 390, 372, 360, 346, 334, 322, 305, 279, 253, 224, 196, 165, 116 }
#define MAH3000_PCT  { 100,  93,  87,  80,  73,  67,  60,  53,  47,  40,  33,  27,  20,  13,   7,   0 }
```

### Fifth log: from a full charge to empty (4 November 2026)

The owner charged the iPod to full and played music until the iPod stopped. The file is `battery-logs/2026-11-04-full-charge-to-empty.txt`.

- The log has one run of 253 samples, from 60 s to 75699 s (21.0 hours). The time between samples is 300–301 s, with no gap.
- The first raw value is 443, and the highest mean is 440. The last raw values are 108, 102 and 92.
- The largest rise is 6 raw units (48686 s: 296 to 302). No sample is near the charger values (476–478). Thus a charger was not connected.
- The fourth column is 1 in each sample.

Raw values at each hour:

| Hour | 0 | 2 | 4 | 6 | 8 | 10 | 12 | 14 | 16 | 18 | 20 | 21 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Raw | 443 | 419 | 408 | 388 | 361 | 338 | 320 | 290 | 245 | 201 | 143 | 92 |

The result of `battery-curve-combine.py` with the fifth log and the second log, and the first log as a check:

| Item | Value |
|---|---|
| Hours that remain at raw 421, fifth log | 19.43 |
| Hours that remain at raw 421, second log | 18.26 (6 % less) |
| Combined curve | Raw 440 to 104, 20.43 hours |
| The 0 % value | 104: the mean of 92 (fifth log) and 116 (second log) |
| Check with the first log, raw 436 to 417 | 2.75 hours in the log, 1.75 hours in the curve (+57 %) |

The difference at raw 421 is less than 10 %, so the mean is correct to use. The first log does not agree at the top of the curve. It did not start from a full charge, and its load is not known. Thus the top 7 % of the curve is the least certain part.

The iPod stopped at raw 92 in the fifth log and at raw 116 in the second log. The stop value is not fixed. With the 0 % value 104, the fifth log gives 2 % at raw 123, 30 minutes before the stop. It gives 0 % from raw 108, 10 minutes before the stop.

The table in `battery_display.c` (version 1.2):

```
#define MAH3000_RAW  { 440, 422, 413, 404, 389, 373, 356, 341, 329, 313, 290, 261, 227, 197, 163, 104 }
#define MAH3000_PCT  { 100,  93,  87,  80,  73,  67,  60,  53,  47,  40,  33,  27,  20,  13,   7,   0 }
```

### Open fault: the stock text at the first play (4 November 2026)

Status: open. The owner stopped the work for now. Continue only if the owner asks.

#### The report

The owner uses Display = Icon + Percent, Custom data and Smoothing On, on a real iPod (version 1.1, flashed from iPodFirm Highlight Test 0.1.260). After a power-on, the first play causes a fault. The fault shows on the menu and on Now Playing. For approximately 5 seconds:

- the percentage is on the battery icon;
- a part of the text is missing;
- the size or the colour of the text is wrong.

Then the text goes back to its correct place without an action.

#### The analysis (static)

The three symptoms are the stock state of the battery label: the stock rectangle at + 0x58, the stock Type record at + 0xc8, and no bit 0x200 at + 0xc0. Thus, for approximately 5 seconds, `hook_show` does not style or move that label.

`hook_show` sets the style and the rectangle again at each call, and 0x1ae6d0 runs approximately 45 times each second (version 0.4). Thus a simple reset of the label by the firmware is not sufficient. The fault needs a period with no correct call.

The possible causes, in order of probability:

| Cause | Mechanism | Agrees with "it stops after 5 seconds"? |
|---|---|---|
| 1. No call | At the first play, the status bar gets the play icon and does a new layout. The layout resets the label. 0x1ae774 and 0x1ae6d0 then do not run for that view until the next battery update | Yes |
| 2. A full view table | `view_slot` has 8 slots (`VIEWS`) and never frees a slot. A new view gets -1, and `hook_show` returns | Only if the view is temporary |
| 3. An early return | `index >= NO_CHILD`, or `ready` is false, while the audio and the disk start | Possible |
| 4. A small view | In a view with `VIEW_SMALL`, layout 0 puts the text and the icon (`SMALL_ICON`) in the same stock box. The text then has the patch font, but it is on the icon and cut | Only if the small view is temporary |

A photo of the fault can separate cause 4 from causes 1–3. With cause 4, the text has the patch font (Podium Sans 14). With causes 1–3, it has the stock font.

#### The emulator test

The owner ran iPodFirm 0.1.261 (battery-display 1.2) in the emulator and played a song after the start. The fault did not show. Thus the fault probably needs a part of the real iPod: the hard drive, which starts to turn at the first play, or real battery values under load.

#### Tools for a later test

- The emulator window accepts `--control=SOCKET` with `--cold`. Thus `peek`, `regs` and `evlog` work while the owner uses the window. Start the program `ipod-emulator` in `ipod-emulator.app` directly with `IPOD_EMULATOR_DATA` set to the iPodFirm profile and `IPODFW_RESET_AFTER=1000000000`, as `EmulatorManager.openWindow` does.
- `IPODFW_REGS_AT=0x1ae6b8,COUNT` records each call of `hook_show` with no change to the patch: r0 is the view, r1 is the index. Each record also adds a marker with the emulated µs to `evlog`. A gap in the records shows cause 1. More than 8 views show cause 2. An index of 0x1c or more shows cause 3.
- On a real iPod, a diagnostic copy of the patch must write the same records to a file, in the same way as `battery-log`. Each record needs the time, the view, the index, the small flag, the slot, `ready`, the reason for a return, and the label rectangle and Type pointer before the patch writes them.

#### Possible fixes (not made)

- Cause 1: find the layout function in Ghidra that resets the label at the first play. Add a hook after it that calls `style_text` and `place_text` for the known battery labels. An alternative is the label draw method 0x244924, only for labels in the `views` table.
- Cause 2: when no slot is free, use the slot of the oldest view.
- Cause 3: keep the last style and rectangle in each path of the return.
- Cause 4: in a small view with Icon + Percent, show only one of the icon and the text.

The branch `battery-show-fix` (worktree `../iPod5.5Firm-battery-show`) is ready for this work. It has no commits yet.

