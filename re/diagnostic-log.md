# The patch diagnostic-log

The test patch [diagnostic-log](../patches/diagnostic-log/patch.json) has the 13 hooks, the log and the file write of [playback-log](playback-log.md), and 8 more hooks. Refer to that note for the playback path and for the logs from the real iPod.

`playback-log` stays in the app, because it is proved on a real iPod. Only one of the two patches can be on at a time, because they use the same hook sites. `Patcher.conflicts` finds this.

All addresses are osos offsets of firmware 1.3.

## The areas

Research: Ghidra 12.1.4, osos 1.3, 30 October 2026. Evidence: Static. The patch has not run in the emulator or on a real iPod yet.

Each area has one option in `patch.json`, with a global variable. An area that is off writes no lines. The hooks stay, because the patcher writes option values after the link. The information block has the line `areas ...`.

| Area | Variable | Site | Result |
|---|---|---|---|
| Playback | `log_playback` | The current hook at 0x1d8260 | The hook gets the event. Type 4 is a key push and type 7 is a release. The key code is bits 16-23 of event + 0x10 (0x2564b0). No new hook is necessary. |
| Memory | `log_memory` | The current hooks | A sample adds a line after a change of 64 KB or more in the free heap. |
| Power and Storage | `log_power` | `bl` at 0x1d9344 | The only call of the sleep sequence 0x1ee8d0. The sequence writes the settings file itself (0xbbf1c), thus a file write is safe here. |
| Power and Storage | `log_power` | `bl` at 0x1dfe18 | The only call of the sleep function 0xb43dc. The function returns after the wake. This hook does not use 0xb45f4, which `flash-keep-awake` uses. |
| Power and Storage | `log_power` | `b` at 0x265cc8 | The storage power. The first instruction is `push {r3-r11, lr}`. The hook also sees the call through `flash-keep-awake` at 0x23344c. |
| Power and Storage | `log_power` | 0x265164, in a sample | The patch logs this word as `channel` and `value`. These labels are not correct. The word is the hardware version `HwVr`, and it does not change (refer to [search-5g.md](search-5g.md#what-the-gate-reads)). The function only reads RAM. |
| Artwork and Files | `log_artwork` | `bl` at 0x2055dc, `bl` at 0x205854 | The artwork lookup 0x1f161c and the image load 0x2258a4 in ArtworkLoadTask. |
| Artwork and Files | `log_artwork` | `b` at 0x8f38c, `b` at 0x8f464 | The file open and the file read. The hooks also time the reads of `album-art` and `cover-flow`, because these patches call the same functions. |
| Performance | `log_performance` | Word at 0x6701f0 | The event method 0x1d81cc. `cover-flow` uses the same word with no chain. The name `cover-flow` sorts first, thus this hook chains to it. |
| Performance | `log_performance` | RAM 0x14983040, in a sample | The idle time of each core, as in `usb-host-probe`. |

Limits:

- A sample runs at most each 30 s, and only at a button or wheel event. A time with no event has no sample. Do not sample more often, because each new line causes a disk write at the next event.
- `ui=` is the longest time in 0x1d81cc. This method does not include each draw of a list.
- The key codes of the click wheel buttons are not proved. The Simple Remote codes are in [firmware-functions.md](../docs/firmware-functions.md). The first log from a real iPod gives the wheel codes.
- A sleep function that does not return loses the lines after the last file write. The file write before the sleep has the line `sleep start`.

## The differences from playback-log 1.4

| Item | `playback-log` 1.4 | `diagnostic-log` 2.0 |
|---|---|---|
| The letter | `g` | `d` |
| The header | `PL01 playback-log 1.3` | `PL02 diagnostic-log 2.0` |
| The file | `iPodFirmPlaybackLog` | `iPodFirmDiagnosticLog` |
| The information block | No area line | The line `areas ...`. The text before the list is at most 384 bytes, not 320. |
| The file write | Only at an event | At an event, and before each sleep |
| The size | 38849 bytes | 41768 bytes |

## Tests

- Swift: `testPatchSizes`, `testPatchMetadata`, `testDiagnosticLogConflicts`, `PlaybackLogTests` (the `PL02` header).
- Python: `test_diagnostic_log_hooks` with the Apple firmware 1.3. Each `expect` value, each hook word and each chain wrapper is correct.
- Not tested in the emulator or on a real iPod.
