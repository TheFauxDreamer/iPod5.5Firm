# Hidden switch files in firmware 1.3

Firmware 1.3 of the iPod Video reads a list of hidden switches from files on the iPod. This note records the list. The firmware does not keep the names as plain text: each 32-bit word holds the characters shifted left by one bit.

All addresses are osos offsets. The research used Ghidra 12.1.4 on 31 October 2026. The switch `_show_voltage` is tested on a real iPod, together with `_enable_options` (31 October 2026). No other switch is tested. No switch is tested in the emulator.

## How to use a switch

CAUTION: Add only one switch for each test. The effect of most switches is not known.

CAUTION: Do not use a switch that has the risk "High" in the tables below.

1. Connect the iPod so that it shows in Finder.
2. Open the folder `iPod_Control/Device/`.
3. Make an empty file with the name `_enable_options`.
4. Make an empty file with the name of the switch.
5. Eject the iPod.
6. Restart the iPod.

The firmware examines only the name of the file. The contents have no effect.

To remove a switch:

1. Connect the iPod so that it shows in Finder.
2. Delete the file of the switch from `iPod_Control/Device/`.
3. Delete `_enable_options` if you use no other switch.
4. Eject the iPod.
5. Restart the iPod.

## Online sources

[Macworld](https://www.macworld.com/article/175199/numberbattery.html) and [Mac OS X Hints](http://hints.macworld.com/article.php?story=20040226061632743) describe `_show_voltage` for older iPods. They use only that file. Macworld gives a value from 0 to approximately 519, and it excludes the iPod photo. Forum reports are on [iLounge](https://forums.ilounge.com/threads/ipod-battery-meter-hack.29256/) and [Apple Community](https://discussions.apple.com/thread/331605).

A web search on 31 October 2026 found no source for `_enable_options` or for the other switches. This does not prove that no source exists.

## How the firmware reads the switches

| Address | Function | Evidence |
|---|---|---|
| 0x1d3ac4 | Reads all the switches. Called from 0xb4abc, in the database load 0xb4a64. Thus the read occurs at the start and after a sync. | Static |
| 0x1d3610 | Clears the switch bytes first. | Static |
| 0x1d4114 | Tests the file `_enable_options`. **If the file is not there, 0x1d3ac4 reads almost no other switch.** | Static |
| 0x122a0c | Tests if a file exists. Only the name counts. | Static |
| 0x1081dfdc | The start of the switch bytes. Script methods read some of them (table near 0x4fd888). | Static |

Each file is in `iPod_Control/Device/`. The byte + 1 stores the result of `_enable_options`, but 0x1d3e10 then writes the result of `/iPod_Control/iTunes/FirstTime` to the same byte. The table has one more path: `Demo Mode` and `Silent` text is near the switch `_dartboard`. These are not decoded.

## The switches

The name is complete for `_go_fast` and `_show_voltage`: the code that ends the name is checked. The other names come from the same decode, without the padding character `X`. The groups come from the names. They are not a firmware structure.

The switch `_enable_options` is not in these tables. It is the gate for all of them. Refer to [How the firmware reads the switches](#how-the-firmware-reads-the-switches).

### Display

| Byte | File | Probable effect | Risk |
|---|---|---|---|
| 0x1081dfe3 | `_show_voltage` | Shows the raw battery number. **Tested on a real iPod.** The display drops the third digit. Refer to [battery.md](battery.md). | Low |
| 0x1081dfde | `_show_numeric_volume` | Probably shows the volume as a number. | Low |
| 0x1081dfed | `_show_brightness` | Probably shows the brightness. | Low |
| 0x1081dfe4 | `_show_speed` | Not known | Not known |
| 0x1081dffd | `_show_cache_size` | Not known | Not known |
| 0x1081dfee | `_black_digits` | Not known | Not known |
| 0x1081dfec | `_autopow_overlay` | Not known | Not known |
| 0x1081e001 | `_caption3staticlines` | Not known. Probably video captions. | Not known |
| 0x1081e002 | `_caption4staticlines` | Not known. Probably video captions. | Not known |

### Development

| Byte | File | Probable effect | Risk |
|---|---|---|---|
| 0x1081dfe5 | `_enable_logging` | Not known. Possibly useful for development. | Not known |
| 0x1081dfdf | `_enable_profiling` | Not known | Not known |
| 0x1081dfff | `_heap_beep` | Not known | Not known |
| 0x1081dfe2 | `_go_fast` | Not known | Not known |
| 0x1081dff2 | `_dartboard` | Not known. `Demo Mode` and `Silent` text is near this switch. | Not known |

### Video

| Byte | File | Probable effect | Risk |
|---|---|---|---|
| 0x1081e000 | `_sync_any_video` | Not known | Not known |
| 0x1081dfea | `_dont_reject_vid` | Not known | Not known |

### Power

| Byte | File | Probable effect | Risk |
|---|---|---|---|
| 0x1081dfeb | `_no_vc0autopower` | Not known | Not known |
| 0x1081dffc | `_short_voicememo` | Not known | Not known |

### USB audio and accessories

| Byte | File | Probable effect | Risk |
|---|---|---|---|
| 0x1081dff7 | `_usb_audio_show_status` | Not known | Not known |
| 0x1081dff8 | `_serial_acc_iap_status` | Not known | Not known |
| 0x1081dffa | `_enable_a46_remote_menu` | Not known | Not known |

### Do not use

| Byte | File | Probable effect | Risk |
|---|---|---|---|
| 0x1081dffb | `_battery_always_low` | The battery value is always 5 (0x1dfe44). | High |
| 0x1081dfe0 | `_disable_cache` | Probably turns off a part that the firmware needs. | High |
| 0x1081dfe8 | `_disable_hibe` | Probably turns off a part that the firmware needs. | High |
| 0x1081dfe6 | `_disable_jpeg_decoder` | Probably turns off a part that the firmware needs. | High |
| 0x1081dffe | `_disable_unsplit_decoders` | Probably turns off a part that the firmware needs. | High |

### Names with no separate byte

The decode also found these names. Their bytes are not separated yet, so their effect is not known. Do not use them until the research finds the bytes.

| Group | Names |
|---|---|
| General | `_locked`, `_unlocked`, `_speed`, `_tcsize` |
| Sleep | `_hibe_sleep`, `_short_deepsleep`, `_no_deepsleep` |
| USB | `_usb_swap_configs`, `_usb_audio_sinewave`, `_usb_audio_resampling_method`, `_usb_audio_negotiation_optional`, `_usb_audio_samplerate_match_style`, `_usb_audio_authentication_optional` |

## Caution

The effect of each switch is an estimate from its name, except `_show_voltage` and `_battery_always_low`. Test one switch at a time.

With `_enable_options` and `_show_voltage`, the static code gives no other change: all the other files are missing, so their bytes stay 0.
