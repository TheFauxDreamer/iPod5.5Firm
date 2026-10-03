# Play latency after idle time (flash storage)

## Symptom

The iPod 5.5G has the stock firmware 1.3 and a flash adapter. The first song after idle time starts after 3–6 s. When a song plays, a new selection starts almost at once.

## Result

The stock firmware switches off the storage power about 1 s after the last access. The next access must switch the power on again. The firmware then waits until the adapter clears BSY. A flash adapter must start its SD card(s) again after a power cut, and this takes seconds.

The firmware's own part of the wake is approximately 15 ms. Thus, a shorter wait in the firmware cannot remove the delay. The patch `patches/flash-keep-awake` keeps the storage on for 2 minutes after each access.

## Findings from other projects

- Rockbox switches the drive power with `GPO32_VAL` (0x70000080) bit 0x40000000 on the iPod Video (`firmware/target/arm/ipod/power-ipod.c`).
- Rockbox wake sequence (`firmware/drivers/ata.c`): power on, wait 250 ms, soft reset, then poll for "ready".
- iFlash adapters report no ATA power management and no SSD flags in IDENTIFY (rockpod issue #37).

## Code in osos 1.3

Offsets are osos file offsets. The CPU address is the same.

| Offset | Function |
|---|---|
| 0x265cc8 | Drive power on (1) or off (0). This is Apple's `ide_power_enable`. It sets GPIO pin 134 (`GPO32_VAL` bit 30, set = off), `DEV_EN` bit 0x2000000 and the GPIOG/H/I/K enables. After power on, it waits 4 ms (0x282870) and 10 µs (0x2828b8). It returns at once if the power is already in the requested state. |
| 0x282cf0 | Set a GPIO pin (pin, value). |
| 0x282870, 0x2828b8 | Busy wait in ms and in µs (`USEC_TIMER`). |
| 0x11c9fc | Task sleep in ms. |
| 0x233478 | ATA object set-up. It keeps the taskfile and controller register addresses in the object. |
| 0x233358 | Drive "set power" method. Argument 0: power on, controller set-up, wait for ready, SET FEATURES. Argument 1: STANDBY IMMEDIATE (vtable +0x54), wait, controller off, power off (call at 0x23344c). |
| 0x232ec8 | Wait for ready after power on: sleep 10 ms, then poll BSY=0 and DRDY=1 each 10 ms. After 10 s, power cycle and poll again (21 s in total). Then reset. |
| 0x142fc0, 0x14316c | ATA commands with a 10 s timeout. After a wake: SET FEATURES 0x03/0x0C (PIO4), 0x03/0x44 (UDMA4), 0x02 (write cache), 0xAA (read look-ahead), 0x05/0x01 (APM level 1). |
| 0x284b0c | Keep-awake task. It has 45 client slots. A client sends type 0 (always on), type 2 (on for a time in ms, at message +0x18), and other types. When no slot is active, the task sends "sleep" to the storage task. The storage task then calls 0x233358 with 1. |
| 0x2823bc | Power-state entry (modes 1, 2, 3, 5). Modes 1 and 2 switch the drive power off at 0x28249c. The sleep function at 0xb43dc uses mode 3 or mode 2. |

Clients of the keep-awake task send 501 ms and 1001 ms. At start, one client sends 15001 ms. Thus, after start the drive stays on for approximately 16 s, and later for approximately 1 s.

## Measurements in the emulator

The iPodFirm emulator patch logs each write to the ATA taskfile, the ATA control register and `GPO32_VAL` (`evlog` command). The measurements below are from stock 1.3.

| Event | Time |
|---|---|
| Power on → ATA reset | 14 ms |
| ATA reset → first read | 1 ms |
| Last access → STANDBY and power off (after the 15 s start keep-awake) | 12.7 s |
| Last write (Settings → About) → STANDBY and power off | 0.26 s |

The emulated drive is ready at once. On a real iPod, the adapter's start time comes after the 14 ms.

These actions read the drive in the emulator after idle time: open Settings, Shuffle Songs. Notes and games do not read it, because the firmware loads them at start. A song from a list does not start, because the emulator has no audio.

## The patch

`patches/flash-keep-awake` replaces `ldr r1, [r4, #0x18]` at 0x284c7c (the time of a type-2 message) with a call to a hook. The hook makes each time that is shorter than 120000 ms equal to 120000 ms. It does not change 0 or 0xffffffff.

All the power paths of the firmware stay the same. After 2 minutes without access, the stock path sends STANDBY and switches the power off. The sleep and shutdown paths do not change.

A first version replaced the power-off call at 0x23344c with a NOP. That version kept the power on in standby. It was not used, because the emulator cannot show if the firmware puts the drive to sleep before mode 3. Then the drive would stay powered while the iPod sleeps.

Test in the emulator: after start, the power stayed on and went off later through the stock path. Shuffle Songs woke the drive and showed Now Playing.

## Open items

- Measure the delay on the real iPod with the patch.
- Measure the battery life with the patch.
- The 120000 ms value is a choice. A longer time gives more fast starts and uses more battery.
