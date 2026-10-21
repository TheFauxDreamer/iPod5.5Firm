# The video player and the video processor

This note records how firmware 1.3 controls the video processor during video playback. The patch [video-log](../patches/video-log/) uses these results. It records each command and each reply in a log file.

## The problem

On the owner's iPod 5.5G, a video does not play (2026-10-21). Select a video: the screen is black, with no picture and no audio. The stock Apple firmware 1.3 gives the same result. MiMusic put the videos on the iPod. Thus the cause is probably in the file or in the iTunesDB record, not in the patches.

## The method

- A Python scan of osos 1.3 for `add rX, pc, #imm` instructions that point to the command strings.
- A scan for the `bl` instructions after each string load.
- Ghidra (`DecompileAt.java`, `FindXrefs.java`, `ListVtable.java`), project osos13.
- The emulator, with the patch `video-log` 1.0 (2026-10-21).

## The command channel

The ARM code controls the Broadcom BCM2722 (VideoCore) with text commands. The video processor replies with text, for example `key=value` pairs.

| Address | Function | Evidence |
|---|---|---|
| 0x287664 | `vc_command(reply, size, format, ...)`. It sends a command and reads the reply. The first instruction is `push {r0-r3}`, thus the function is variadic. Result: 0 if the reply is correct, -1 if the channel is not open. 35 callers. | Ghidra, emulator |
| 0x287110 | The same as 0x287664, with no check of the send result. Callers: 0x289134 and 0x28921c (`load_application %s`, `end_application %d`). | Ghidra |
| 0x2874f0 | Sends a command with no reply (format, arguments in r1–r3). Caller: 0xcbf58. | Ghidra |
| 0xe9358 | Formats and sends one command (format, pointer to the arguments). It takes the lock 0x123000. It formats with 0x7b114 into a 256-byte buffer on the stack and sends with 0x28861c. Result: 0, or -1 if the channel is not open (the word at +4 of the channel object is negative). | Ghidra, emulator |
| 0x2872c0 | Reads the reply into a buffer (buffer, size). It calls 0x2872fc until the reply is complete. Then 0x287140 releases the lock. Result: 0 if the reply has more than one byte, else 1. | Ghidra |
| 0x123000 | Takes the lock of the channel (0xc9a84). | Ghidra |
| 0x287140 | Reads the rest of the reply and releases the lock (0xc8294). | Ghidra |
| 0x7b114 | `vsnprintf(buffer, size, format, arguments)`. The arguments are a pointer to the words of a variadic call. | Ghidra, emulator |
| 0x7b240 | `snprintf(buffer, size, format, ...)`. | Ghidra, emulator |

Thus all commands go through 0xe9358, and all replies go through 0x2872c0. A hook on these two functions records the full traffic.

## The commands

The table gives the call sites of the commands. The player object has its reply buffer at +0x33 (0x100 bytes).

| Command | Call site | Function | Vtable slot (0x671dc0) |
|---|---|---|---|
| `set_vll_dir %s` | 0x1afc28 | 0x1afb60 (the start of VideoCore: `vmcs.bin`, `RenderServer.bin`) | – |
| `load_application %s`, `end_application %d` | 0x289258, 0x28917c | 0x28921c, 0x289134 | – |
| `mp_selectplay passthru:%s %d` | 0x1fa428 | 0x1fa394 | +0x34 |
| `mp_play` | 0x1f8ed4 | 0x1f8e84 | +0x40 |
| `mp_pause` | 0x1fa5cc | 0x1fa5b4 | +0x3c |
| `mp_stop` | 0x1f91e4 | 0x1f91bc | +0x1c |
| `mp_seek %d` | 0x1fa4a8 | 0x1fa470 | +0x54 |
| `mp_step %d` | 0x1fa4fc | 0x1fa4c4 | +0x50 |
| `audio_enable %d` | 0x1f9130 | 0x1f90f4 | – |
| `mp_region display=%d dest="%d %d %d %d" mode=%s` | 0x1f9320, 0x1f93a8 | 0x1f92f4, 0x1f9354 | +0x6c, +0x70 |
| `mp_get_status` | 0x1f9440 | 0x1f9404 | – |
| `mp_get_stats video`, `mp_get_stats audio`, `power_management get_info` | 0x1f97b0, 0x1f9938 | 0x1f9754 | – |
| `display_control ...` | 0x163b84, 0x164ae4 and others | 0x163b64, 0x164ac8 | – |
| `ss_selectplay`, `ss_region`, `ss_stop`, `ss_get_status` | 0x1c7750–0x1c7cbc | 0x1c76f0–0x1c7a3c (the photo slide show) | – |

`mp_selectplay passthru:%s %d` gives a short name at +0x29 of the player, not the file path. Thus the ARM code probably reads the MP4 file itself (the string `Mp4Parser` is at 0x232a60) and passes the data to VideoCore (`passthruhandler.vll`).

### The status reply

0x1f9404 reads these keys from the reply of `mp_get_status`:

| Key | Values | Result |
|---|---|---|
| `duration`, `elapsed` | numbers | The length and the position |
| `paused` | `yes`, `idle`, `eof` | Flags 2 (`idle`) and 4 (`eof`) |
| `suspended` | `yes` | Flag 0x10 |
| `mode` | (0x1f96f8), `rew` | Flags 0x20 and 0x40 |
| `state` | `idle`, `playstill`, `play` | 0, 1, 2 |
| `substate` | `decoding`, `ready`, `stopping`, `starting` | 0, 1, 2, 3 |

A reply with `paused=eof` directly after `mp_play` means that the player found no data. `substate=starting` for a long time means that the decoder gets no frames.

### The statistics

0x1f9754 sends `mp_get_stats video` or `mp_get_stats audio` with a 0x400-byte buffer. It reads `last_frame_time`, `num_frame_buffers`, `lost_frame_asserts` (with `_discards`, `_overflow`, `_starvation`, `_packetorder`, `_decoding`), `total_bytes_decoded`, `min_time_ahead`, `max_time_ahead` and `last_displayed_frame`. Then it sends `power_management get_info` (`core_freq_khz`). The callers are 0x1f9c04 and 0x1f9dfc, which print the text "lost frames - decoder (failed to decode)".

### The `.log` method

0x1fa278 (vtable slot +0x7c) makes the name `"%s%s"` of a string at +0xc and `.log` with 0x7b240. Then it calls the method +0x74 of the object with this name. No caller was found (the slot is called through the vtable). It is not known if Apple writes a statistics file. The patch does not use this method.

## Emulator result (2026-10-21)

The emulator has no video processor. With `video-log` 1.0, the start of the iPod gave these lines:

```text
     0.000 > set_vll_dir /Resources/VideoCore/Library  [send -1]
     0.002 > display_control 0 freeze=0  [send -1]
     5.083 > display_control 0 model=2 power=-2  [send -1]
```

- The hooks format the commands correctly.
- `[send -1]`: the channel is not open in the emulator. Thus no reply comes, and the emulator cannot play a video.
- A button press wrote the log file (the header line had `writes=1`).
- The main menu and the Videos menu operated.

## Real iPod result (2026-10-21)

The owner played the video Big Buck Bunny (`F05/SGDN.mp4`, from MiMusic, copied with no conversion) with `video-log` 1.0. The screen stayed black, with no audio. A part of the log:

```text
41.421 > load_application mplayer.vll
41.421 < 0 task=1028
41.422 > mp_setvol 0
41.422 < 0 error=1 error_msg="Command not registered"
41.586 > mp_selectplay passthru:0 0
41.588 < 0 state=play substate=starting duration=unknown elapsed=0 ...      (mp_get_status)
41.843 < 0 state=play substate=running duration=596459 elapsed=0 ...       (mp_get_status)
42.439 < 0 state=play substate=running duration=596459 elapsed=0 ...       (repeated until 52.651)
52.651 < 0 last_frame_time=4916 num_frame_buffers=4 ... total_bytes_decoded=249 ... last_displayed_frame=3 ... Disp param1=320 Disp param2=180
52.653 < 0 last_frame_time=4885 num_frame_buffers=1 ... total_bytes_decoded=397 ... Disp num_bytes=397 Disp param1=1024
```

Results:

- The channel to the video processor operates. `mplayer.vll` loads, and the player starts.
- The player knows the length (596459 ms, the same as the `mvhd` of the file) and the picture size (320 × 180).
- `elapsed` stays 0 for 11 s. The video decoder got only 249 bytes (approximately 3 frames). The audio decoder got only one AAC frame (397 bytes). No lost frames are counted.
- Thus the player stops after the first samples, because the ARM code does not send more data. The video processor does not refuse the stream.
- `mp_setvol 0` gives "Command not registered" also in the normal sequence. This is probably not the cause.

The iTunesDB record of the video is correct: file type `M4V `, media type 2 (movie), length 596458 ms, sample count 28629984 (48 kHz), movie flag 1.

### The structure of the video files on the iPod

| File | Source | `ftyp` | `moov` | Chunks | Video | Audio |
|---|---|---|---|---|---|---|
| `F05/SGDN.mp4` (Big Buck Bunny) | Copied with no conversion | `isom`, `mp41` | After `mdat` (at the end) | 1 sample in each chunk: 14315 video and 27949 audio chunks | H.264 Baseline 1.3, 320 × 180, 24 fps, no `uuid` atom | AAC, 48 kHz |
| `F04/FZLB.mp4` (Gundam prologue) | Copied with no conversion | `mp42` | At the end | Video: 1 sample in each chunk (34190) | H.264 Baseline 1.3, 320 × 176, `uuid` atom | AAC, 44.1 kHz |
| `F06/UEPB.m4v` (T2 clip) | Converted by MiMusic | `M4V ` | At the start | 118 video and 119 audio chunks (approximately 0.5 s each) | H.264 Baseline 3.0, 640 × 352, `uuid` atom | AAC, 44.1 kHz |

The files from iTunes have the `moov` at the start and chunks of approximately 0.5 s. The two copied files do not have this structure. This is a probable cause: the ARM code possibly reads the sample tables in a limited buffer, or it expects the `moov` at the start. It is not confirmed.

## Next steps

1. The owner runs the test with `F06/UEPB.m4v` (the MiMusic conversion, with the `moov` at the start and 0.5 s chunks). If this video plays, the cause is the structure of the copied files. Then MiMusic must convert or rewrite each video, also when the codec is correct.
2. Compare the two logs. Look for these signs:
   - no `mp_selectplay` or `mp_play`: the ARM code refused the file before the player started (the iTunesDB record or the MP4 parser);
   - `paused=eof` or `substate=starting` after `mp_play`: the player started but got no data;
   - lost frames in `mp_get_stats video`: the decoder refused the stream (the codec, the profile or the size).
3. If the log shows no command, find the MP4 parser (the code that uses the string at 0x232a60). Then add hooks in the parser and in the DRM check 0xe2d30.
