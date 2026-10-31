# Hidden switch files in firmware 1.3

Firmware 1.3 of the iPod Video reads a list of hidden switches from files on the iPod. This note records the list. The firmware does not keep the names as plain text: each 32-bit word holds the characters shifted left by one bit.

All addresses are osos offsets. The research used Ghidra 12.1.4 on 31 October 2026. No switch is tested in the emulator or on a real iPod.

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

The name is complete for `_go_fast` and `_show_voltage`: the code that ends the name is checked. The other names come from the same decode, without the padding character `X`.

| Byte | File | Probable effect |
|---|---|---|
| 0x1081dfe2 | `_go_fast` | Not known |
| 0x1081dfe3 | `_show_voltage` | Shows the raw battery number. Refer to [battery.md](battery.md). |
| 0x1081dfde | `_show_numeric_volume` | Shows the volume as a number |
| 0x1081dfed | `_show_brightness` | Shows the brightness |
| 0x1081dfe4 | `_show_speed` | Not known |
| 0x1081dffd | `_show_cache_size` | Not known |
| 0x1081dfee | `_black_digits` | Not known |
| 0x1081dffb | `_battery_always_low` | The battery value is always 5 (0x1dfe44). Do not use it. |
| 0x1081dfe0 | `_disable_cache` | Do not use it. |
| 0x1081dfe8 | `_disable_hibe` | Do not use it. |
| 0x1081dfe6 | `_disable_jpeg_decoder` | Do not use it. |
| 0x1081dffe | `_disable_unsplit_decoders` | Do not use it. |
| 0x1081dfe5 | `_enable_logging` | Not known. Possibly useful for development. |
| 0x1081dfdf | `_enable_profiling` | Not known |
| 0x1081dff2 | `_dartboard` | Not known |
| 0x1081dffa | `_enable_a46_remote_menu` | Not known |
| 0x1081e000 | `_sync_any_video` | Not known |
| 0x1081dfea | `_dont_reject_vid` | Not known |
| 0x1081dfff | `_heap_beep` | Not known |
| 0x1081dff8 | `_serial_acc_iap_status` | Not known |
| 0x1081dff7 | `_usb_audio_show_status` | Not known |
| 0x1081dffc | `_short_voicememo` | Not known |
| 0x1081dfeb | `_no_vc0autopower` | Not known |
| 0x1081dfec | `_autopow_overlay` | Not known |
| 0x1081e001, 0x1081e002 | `_caption3staticlines`, `_caption4staticlines` | Not known |

The decode also found these names. Their bytes are not separated yet: `_locked`, `_unlocked`, `_speed`, `_hibe_sleep`, `_tcsize`, `_usb_swap_configs`, `_short_deepsleep`, `_no_deepsleep`, `_usb_audio_sinewave`, `_usb_audio_resampling_method`, `_usb_audio_negotiation_optional`, `_usb_audio_samplerate_match_style` and `_usb_audio_authentication_optional`.

## Caution

The effect of each switch is an estimate from its name, except `_show_voltage` and `_battery_always_low`. Test one switch at a time.

With `_enable_options` and `_show_voltage`, the static code gives no other change: all the other files are missing, so their bytes stay 0.
