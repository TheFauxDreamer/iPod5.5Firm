# Play latency after idle time (flash storage)

## Symptom

The iPod 5.5G has stock firmware 1.3 and a flash adapter. The first play after idle time takes 3–6 s. When a song plays, a new selection starts almost at once.

This pattern shows that the delay comes from the storage wake, not from the database or the audio decoder.

## Findings from other projects

- Rockbox switches the drive power with `GPO32_VAL` (0x70000080) bit 0x40000000 on the iPod Video (`firmware/target/arm/ipod/power-ipod.c`).
- Rockbox wake sequence (`firmware/drivers/ata.c`): power on, wait 250 ms (`sleep(HZ/4)`), soft reset, then poll for "ready" with retries.
- Rockbox default: STANDBY after 5 s of idle time, then power off after 2 s more (`ATA_POWER_OFF_TIMEOUT`).
- iFlash adapters report no ATA power management and no SSD flags in IDENTIFY (rockpod issue #37). Thus a firmware cannot identify the adapter as flash from the standard flags.

## Findings in osos 1.3

Offsets are osos file offsets.

| Offset | Item |
|---|---|
| 0x233478 | ATA object set-up. It stores the taskfile register addresses (0xC30001E4 to 0xC30001FC) and the controller registers (0xC3000000, 0xC30003F8, 0xC3000400–0xC300040C) in the object. |
| 0x233424–0x23343C | A loop that calls a delay function (0x11C9FC) with 10 until the object state at +0x14 is `free` (0x66726565). |
| 0x1C7F58 | GPO base selection. If the chip ID is "32" (PP5022), it stores 0x70000080 (`GPO32_VAL`) at 0x10833CAC+0xC. Else it stores 0x70000020. |

The drive power code reads the GPO base from the pointer at 0x10833CB8. The code does not use a literal 0x70000080. Thus a static search for the literal does not find the power code.

The emulator (siggifly/ipod-emulator) shows that RetailOS sends 0xE0 STANDBY IMMEDIATE. The emulator answers the power commands at once and does not model a spin-up time. A fixed wait in the firmware still runs in the emulator.

## Next steps

1. Find the code that writes bit 0x40000000 through the pointer at 0x10833CB8. Use a watch on the GPO32 register in the emulator, or search for `0x10833cac` references.
2. Add an ATA command log with an instruction-count timestamp to the iPodFirm emulator patch.
3. In the emulator, wait for STANDBY, click Play, and measure the time from the power-on to the first READ.
4. Find the delay calls in that interval, and record their values here.
