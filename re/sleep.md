# Sleep in osos 1.3

## Symptom

After the owner selects Sleep, the music pauses and the wheel does not respond. The screen stays on, and the backlight dims with the backlight timer. A button wakes the iPod. The problem occurs after a computer session, and it also occurs with the stock firmware (for approximately 1 minute). It does not occur after a wall charger. With the 30-minute `flash-keep-awake` patch, the screen did not go off after more than 2 minutes.

## The Sleep path

Offsets are osos file offsets. The CPU address is the same.

1. App command 7 (0x1e8cd4) calls the Sleep item handler 0x1d83fc at 0x1e8ce8, with the power controller (`app + 0x3e4`). A table entry at 0x69fd2c also points to 0x1d83fc.
2. 0x1d83fc turns the backlight off (0xb4638) and starts the idle timer (`ctl + 0x48`, 500 ms).
3. The idle timer handler 0x1d8a40 sleeps only if the gate 0x1d938c passes. The gate is 0x1d8d9c, then 0x1d8444 (0x1d8670 and 0x1d8718). If the gate does not pass, the handler starts the timer again.
4. When the gate passes, the handler calls 0x1ee8d0(app, flag).
5. 0x1ee8d0 saves the settings and empties the memory cache manager (0x1ed828, 0x19ff0c: the users give back their memory; refer to usb-host.md). Then it calls the sleep method (vtable 0x670720, offset 0x70, 0x1dfdd4).
6. 0x1dfdd4 calls the sleep function 0xb43dc. 0xb43dc turns the display off (0xb7c64(0)), sends keep-awake message type 4 (0x94e08) and enters power mode 2 or 3 (0x2823bc).

Marker test in the emulator (stock firmware): the Sleep item ran 0x1d83fc, then the idle gate. The gate did not pass, and 0x1ee8d0 did not run.

## The gate 0x1d8670

The gate passes only if all these are true:

- `app + 0x48a` is 0 (0x1ed9e8).
- Component 0x1afd74: byte +0x2a is 0.
- Component 0x3d00 (0x1c1f5c): byte +0x66 is 0. A voice memo recording sets it.
- 0x197e70 returns true (a state at +0x1c is 1–5 or 7).
- 0x154150 and 0x161534 return true.
- Not (A and not B and not C). A is vtable offset 0xac (0xffff8), B is offset 0xb4 (external power, 0x9e664) and C is offset 0xb8 (always 0).

Then 0x1d8718 calls 0x94cec. 0x94cec returns 1 if any of the 45 keep-awake slots is active, and then the gate does not pass. See [play-latency.md](play-latency.md).

## Power test

0x1ee8d0 does not sleep if 0x1ecc8c (offset 0xb4, 0x9e664) returns true and offset 0xbc (`+0x20`) is 0. It then sets the "sleep pending" flag (+0x487) and keeps the display on (offset 0x6c: 0xb7c64(1)). This is Apple's behaviour on power.

0x9e664 uses saved copies of the power pins. Three monitor objects keep them (byte +6, updated by 0x163ffc):

| Object | Pin | Meaning |
|---|---|---|
| 0x1081ff2c | GPIOL bit 0x08, low = power | FireWire or charger |
| 0x1081ff34 | GPIOL bit 0x10, high = power | USB (0x265698 must also not return 1) |
| 0x1081ff30 | GPIOL bit 0x20 | Used by the gate (A). Function not known. |

## The patch sleep-now

- The hooks at 0x69fd2c (word) and 0x1e8ce8 (bl) call 0x1d83fc. Then they stop the timers +0x48 and +0x74 and call 0x1d9308. 0x1d9308 is the sleep part of the timer handler 0x1d8cd0 (also the end of a long Play push in that handler). It calls 0x1ee8d0 and, after the wake, starts the idle timer again (0x1d813c).
- The hook at 0x1ee930 replaces the power test only during a forced sleep. It reads GPIOL (0x6000d13c) directly. On real power, the Apple behaviour stays.
- If a voice memo records, the hooks do not force a sleep.

Test in the emulator: the Sleep item ran the hook, the sleep part, the power test (no power) and the real sleep branch. The firmware wrote the cache to the storage (ATA 0xCA). Then 0xb43dc called 0xb7c64(0). The emulator stops after this point, also with the stock firmware, because it does not model the hardware sleep. After a restart, the language and the Sleep item setting were kept. Thus the settings were saved.

## Open items

- Test on the real iPod: after a computer session, during playback, and on a charger.
- A long push of Play: the path is not known. The 5000 ms timer of key 0x6e (0x1d8570, timer +0xf0, 0x1d9244) posts screen 0x63f2 and does not call the Sleep handlers. The emulator cannot send a long Play push that the firmware accepts. If a long push of Play sends app command 7, the hook at 0x1e8ce8 covers it.
- Why the stock firmware defers Sleep after a computer session.
