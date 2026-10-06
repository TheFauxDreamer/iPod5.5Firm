# Backlight Timer in osos 1.3

Offsets are osos file offsets. The CPU address is the same.

## The menu

Settings → Backlight Timer is Menu resource -138 (main block, data at 0x4b069c). The menu has a 4-byte count and 7 items of 40 bytes. In each item:

| Offset | Content |
|---|---|
| +24 | i16: string id of the text |
| +26 | u8: position (8–14) |
| +28 | u16: value that the item sends (0x6032–0x603a) |
| +30 | u16: 0x6000 |
| +32 | i16: string id again |

| Value | Apple item | String |
|---|---|---|
| 0x6032 | Off | -139 |
| 0x6033 | none | — |
| 0x6034 | 2 Seconds | -140 |
| 0x6035 | 5 Seconds | -141 |
| 0x6036 | 10 Seconds | -142 |
| 0x6037 | 15 Seconds | -143 |
| 0x6038 | 20 Seconds | -144 |
| 0x6039 | none | — |
| 0x603a | Always On | -145 |

## The setting

1. The Settings controller (vtable 0x66c8c0) gets command 0x6031 in 0x1919d8. It stores `value - 0x32` (0–8) in its byte +0x28.
2. The setter 0xb2e74 stores the same number in the settings at +0xaf8. The getter is 0x9b240.
3. 0x190b00 shows the check mark on the item with the value `number + 0x6032`.
4. 0x193b90 copies the setting and posts event 0x60000006 when the number changes.

## The conversion to seconds

The conversion is not in ARM code. A script in TCmd resource 9088 does it. The script is a switch on the value at 0x4ba9f9. Each case has 6 bytes: `58 <value>` and `77 <offset>`. The offset is relative to the case. Each body pushes the seconds (`58 <u16>`, or `3e` for 0 and `3f` for 1) and calls a native method (`57 00 00 02`).

| Value | Seconds |
|---|---|
| 0x6032 | 0 |
| 0x6033 | 1 |
| 0x6034 | 2 |
| 0x6035 | 5 |
| 0x6036 | 10 |
| 0x6037 | 15 |
| 0x6038 | 20 |
| 0x6039 | 0xfffe (at 0x4baa76) |
| 0x603a | 0xffff |
| other | 10 |

The native method is 0x1eb65c. It writes the seconds to the app object at +0x444. The method table has the setter at 0x4fcea0 and the getter 0x254c1c at 0x4fce98. The script VM calls the methods through 0x120bf0.

The idle controller (0x1d847c and 0x12ec5c) reads +0x444 through 0x1bba98. It starts the timer +0x1c with `seconds * 1000` ms. The value 0xffff starts no timer (Always On). The value 0xfffe gives 10 seconds.

Emulator test (stock firmware): at boot, the setter wrote 10 to +0x444 two times (the default is 10 Seconds).

## The patch backlight-60s

- The case 0x6039 pushes 60 (`58 00 3c` at 0x4baa75) in place of 0xfffe.
- Menu items 1–5 become 5, 10, 15, 20 Seconds and 60 Seconds (value 0x6039, string -140).
- String -140 becomes "60 Seconds" in each language. In Finnish, "60 s" is too long for the string area, thus the patch uses "60s".

Emulator test: the menu showed Off, 5, 10, 15, 20, 60 Seconds and Always On. The selection of 60 Seconds operated. The emulator dimmer model did not change level in 90 seconds after the last button push. Thus, the emulator cannot measure the backlight time.

## Open items

- Measure the backlight time on the real iPod.
