# Album artwork in the Albums list: research notes

This document records the research for the album artwork feature. The firmware is Apple RetailOS 1.3 for the iPod Video.

## Tools

| Tool | Location | Function |
|---|---|---|
| Ghidra 12.1.4 | `~/Library/Application Support/iPodFirm/tools/` | Disassembler and decompiler. |
| Java (Temurin JDK 21) | `~/Library/Application Support/iPodFirm/tools/` | Runtime for Ghidra. |
| Ghidra project | `~/Library/Application Support/iPodFirm/re/ghidra-project/` | The analyzed osos (base address 0x0). |
| `re/ghidra-scripts/DecompileAt.java` | This repository | Writes the C code, the callers and the callees of the functions at given addresses. |
| `re/ghidra-scripts/SetArmOptions.java` | This repository | Pre-script. Turns on the "ARM Aggressive Instruction Finder". |
| Emulator patch `0001-ipodfirm-instrumentation.patch` | `mac/Resources/emulator-patches/` | Adds the `hist` and `regs` commands. `hist` gives the count of instructions in each 64-byte block of code. `regs` gives the registers at the address in `IPODFW_REGS_AT`. |
| `ipodfw.emucontrol` | `src/ipodfw/emucontrol.py` | Python control of the emulator. |

The Ghidra download does not include the native decompiler for Apple silicon. Build it with `support/gradle/gradlew buildNatives`. Then copy `build/os/mac_arm_64/*` to `os/mac_arm_64/` in each module.

## How to run Ghidra without a window

Use these commands to decompile functions:

```sh
T="$HOME/Library/Application Support/iPodFirm/tools"
R="$HOME/Library/Application Support/iPodFirm/re"
JAVA_HOME="$T/jdk-21.0.12.1+1/Contents/Home" \
  "$T/ghidra_12.1.4_PUBLIC/support/analyzeHeadless" "$R/ghidra-project" osos13 \
  -process osos-1.3.bin -noanalysis -readOnly \
  -scriptPath re/ghidra-scripts -postScript DecompileAt.java OUT.c 135b2c 223420
```

## Facts

### Memory addresses

The code runs at addresses that are equal to the offsets in the osos image. The base address in Ghidra is 0x0.

### Code that runs when a list scrolls

The emulator recorded the code that ran in three conditions:

1. The Albums list was shown, and no button was pushed.
2. The Albums list scrolled one row.
3. The Music menu scrolled one row.

Results:

- 515 blocks of 64 bytes ran when either list scrolled. This is the general list code.
- 53 blocks ran only when the Albums list scrolled. Most of them are near 0x223000.

### Functions that are identified

| Address | Function | Evidence |
|---|---|---|
| `0x2234dc` | Reads one UTF-8 character and returns a UTF-16 value. | The code examines the high bits 0x80, 0xC0 and 0xE0. |
| `0x223420` | Converts a UTF-8 string to a new UTF-16 string. | Calls `0x224414` (length), `0x25a944` (memory allocation) and `0x224278` (next character). |
| `0x224190` | Text function for the database strings. | Calls the same text functions. It runs only for the Albums list. |
| `0x135b2c` | **Bytecode interpreter.** | Reads one opcode byte, uses an opcode table at `DAT_00136a6c`, then executes a `switch` with stack, logic, shift and compare operations. |
| `0x122b28` | Calls the interpreter. | It is in the general list code. |

### The bytecode interpreter is a JavaScript engine

The interpreter at `0x135b2c` is a version of Mozilla SpiderMonkey (JavaScript 1.5). The evidence:

- The value `0x80000001` is `JSVAL_VOID`.
- The masks `0x3ffffffe` and `0xc0000001` agree with the SpiderMonkey tagged values.
- The opcode numbers agree with the SpiderMonkey 1.5 opcode table. Examples: 0x06 `GOTO`, 0x07 `IFEQ`, 0x0F `BITOR`, 0x18 `LSH`, 0x35 `GETPROP`, 0x39 `PUSHOBJ`, 0x3A `CALL`, 0x3B `NAME`.
- The opcode table (`JSCodeSpec`) is at RAM address `0x1083de9c`.

The firmware does not contain JavaScript source text or the names "SpiderMonkey" or "Mozilla".

### The location of the scripts

The emulator recorded the bytecode address at each opcode (instruction `0x135b84`, register r0). One scroll of the Albums list ran 96 opcodes. All of them were in osos offsets `0x4b5f6a` to `0x4c4757`.

These offsets are in the **`TCmd` resource, ID 9088, 91,662 bytes**, in the main resource block (osos offset `0x4b441c`). Thus `TCmd` contains the compiled JavaScript of the user interface. iPodWizard did not decode this resource.

### The rsrc image

The rsrc image contains a FAT16 file system at offset 0x600. `ipodfw.fat16` reads it. It contains only these files:

- `/Resources/Fonts/*.ttf`: the fonts of the user interface, for example `PodiumSans18.ttf`.
- `/Resources/VideoCore/`: programs for the Broadcom video processor.

## Conclusion at this time

1. The user interface has two parts. Native ARM code draws the screen. Compiled JavaScript in the `TCmd` resource controls the behavior.
2. One scroll runs only 96 opcodes. Thus native code draws the rows of the list.
3. A change to the `TCmd` bytecode can change the behavior of the interface without an ARM patch.

## Next tasks

1. Decode the structure of the `TCmd` resource: the scripts, the atoms (names) and the functions.
2. Find the names of the native functions that the scripts call. These are the interface between the scripts and the native code.
3. Find the native code that draws one row of a list. Use the histogram of a list that has many rows.
4. Find the function that reads album artwork for the Now Playing screen.

## Result: the album-art patch

The patch is in [patches/album-art/](../patches/album-art/). It is complete and has tests in the emulator. Version 2.0 gets the album covers from the artwork of the iPod and draws with the firmware blit. Refer to [album-art-v2.md](album-art-v2.md).

### How it operates

1. Two vtable entries are replaced:
   - `0x66e470` (draw method `0x1bb260` of the list-row label, type 0x3180);
   - `0x677a14` (draw method `0x244924` of the general label, type 0x1580).
2. The wrapper calculates the FNV-1a hash of the text and finds it in the thumbnail file.
3. The wrapper moves the left edge of the label (view + 0x5c) 24 pixels to the right, calls the original method, and restores the edge.
4. The wrapper prepares the graphics context again (`0x21a27c`) and draws the thumbnail as runs of filled rectangles (`0x211a00`).

### Facts found during the work

- A rectangle is {top, left, bottom, right}. A colour is four bytes R, G, B, A.
- In the graphics context, +0x2c is the x origin and +0x30 is the y origin.
- File functions: open `0x8f38c` (mode `'data'`), read `0x8f464`, seek `0x8f5c4` (64-bit position in r2:r3), close `0x8f184`. Paths use backslashes.
- Memory allocation: `0x25a974`.
- Some draws of a highlighted row with a long title pass a structure in place of the text. The first byte of the structure is less than 0x20. The patch then uses the album from the last draw of the same view.
- A list draws all its rows with one template cell (class 0x66b4dc) and one label view. The highlighted row has a second template cell.
- The children of a view are in a list at view + 0x78: the count is at + 0x7c, the array pointer at + 0x80.
- The u16 at view + 0x1c is the layout element ID. The data source of the list (for example `FUN_001ec614`) uses this ID to select the data for each row.
- Element IDs of the labels, from the emulator:

  | Row | Label ID |
  |---|---|
  | Album in the Albums list (normal and highlighted) | 0x6421 |
  | Song in a song list (normal) | 0x641f |
  | Song in a song list (highlighted) | 0x641e |
  | Playlist | 0x6425 |
  | Menu item | 0x301 |

- The album-art patch draws a thumbnail only for the element IDs 0x6421 (album) and 0x6425 (playlist). Before this check, a song with the same title as an album got the thumbnail.
- The playlist label uses the ID 0x6425 in the normal row and in the highlighted row. The emulator confirmed this on 2026-10-06: the highlighted row showed the playlist thumbnail, not the album thumbnail. On-The-Go has no thumbnail, because iTunesDB does not contain it.
- For a playlist row, the patch calculates the FNV-1a hash of the byte 0x01 and the name. Thus a playlist and an album with the same name have different entries in the thumbnail file.
- The ">" arrow is picture 24268 (8 × 11) in a picture view (class 0x66d89c, element 0x5ecc). In a song row, the same place has element 0x63eb: the speaker (picture 24273) for the song that plays, or no picture. A row without an arrow has a picture view with a width of 0.
- The emulator often ignores a `wheel` command. Make a screenshot after each `wheel` command, and send the command again if the highlight did not move.
- The emulator `make-disk` command makes the osos length 0x600 bytes too short. `ipodfw.emudrive` and `EmulatorDrive` correct this.

## Thumbnails after a sync

The album-art patch loaded the thumbnail file one time. New albums showed only after a restart of the iPod (found on the real iPod).

- iPodFirm writes a stamp at +0x0C of the file: the FNV-1a hash of the entry table.
- After 100 list labels without a thumbnail, the patch reads the 16-byte header again. If the header changed, it frees the old data with `fw_free` (0x25a8e4, the same pool 0x1081da00 as `fw_alloc`) and loads the file again.
- Emulator test (threshold 3): 52 header checks without a change caused no reload. After the file was replaced in the drive image, the patch reloaded it, and the Albums list showed the thumbnails of the new file. The UI continued to operate.

### Reload after a pause (6 October 2026)

On the real iPod, new thumbnails still showed only after a restart. There were two causes:

- The patch counted only labels without a thumbnail. One or two new albums seldom gave 100 such labels. Changed artwork and playlist labels gave none, because each of those rows has a thumbnail.
- The stamp was the hash of the entry table only. New artwork for the same albums gave the same header.

The changes:

- The stamp is now the FNV-1a hash of all the bytes after the header. iPodFirm, `albumart.py` and MiMusic write the same value.
- The patch reads `USEC_TIMER` (0x60005010) at each album label and each playlist label. After a gap of 20 seconds or more, it reads the header again. A sync always gives such a gap, because no list shows during the USB session.
- The count of labels without a thumbnail and the retry after 200 draws are removed. The gap check does both tasks. The code is 3184 bytes (was 3168).

Emulator test (6 October 2026, instrumented emulator, test library with six albums):

- Two thumbnail files had the same six albums. File A had red thumbnails and file B had blue thumbnails. Both files had 4864 bytes.
- With file A, Albums showed red thumbnails. `state` was 1 and the loaded stamp was 0x6eb5283c (file A).
- File B replaced file A at the same sectors of the drive image. No restart occurred.
- After a gap, Albums showed blue thumbnails. The loaded stamp was 0x6e4fd0bc (file B).
- File A replaced file B again. Albums showed red thumbnails, and the loaded stamp was 0x6eb5283c again.
- In the first reload, the bytes 0x1200–0x12ff of the RAM copy (the last part-sector of the file) had the old pixels. The last 6 rows of one thumbnail stayed red. All other bytes were correct. Possibly the firmware sector cache kept the old sector, because the test changed the drive without a USB session.
- The emulator moves its clock forward while the iPod is idle. Thus the test could not make a gap of less than 20 seconds, and that case is not tested.

The timer version was not flashed to a real iPod. The next version replaced it.

### Reload after a USB session (6 October 2026)

The owner asked for a reload only after a sync or a disconnection, not after each pause.

Ghidra results:

- 0xb4a64 loads the music database. It opens `iPod_Control\iTunes\iTunesDB` (string 0xb4de0 and 0xb4df8).
- At 0xb4ad4, the load calls 0x213c5c with the event 0xf. 0x213c5c adds an event to the usage log. The instruction is `bl 0x213c5c` (0xeb057c60), with r1 = 0xf and r2 = 0.
- 0x213cd4 gives the name of each usage-log event. Event 0xe is "Enter Disk Mode", and event 0xf is "Exit Disk Mode".
- Two functions call 0xb4a64. 0xa2310 makes the database object at the start (call at 0xa23fc). 0x1edb9c loads the database again if the flag at +0x489 is 0 (`blne` at 0x1ed2d0).
- The call at 0xb4ad4 is in the branch where 0xaf528 returns 0. The database is read from `iTunesDB` only in this branch.

The change:

- A third hook replaces the `bl` at 0xb4ad4 with `bl hook_db_loaded`. The hook calls 0x213c5c with the same arguments and sets the flag `db_loaded`.
- At the next album label or playlist label, the patch clears the flag and reads the header again. If there was no file, it tries to load the file.
- The timer check is removed. The code is 3080 bytes (was 3184).

Emulator test (6 October 2026, the same files A and B):

- The hook ran one time, 0.30 s after the start (marker at 0x736188).
- Albums showed the red thumbnails of file A. `db_loaded` was 0 again.
- File B replaced file A in the drive image. After approximately 600 emulated seconds, Albums still showed red thumbnails, and the loaded stamp was 0x6eb5283c (file A). Thus the patch did not read the file again without a USB session.
- The emulator has no USB. Thus the reload after a USB session is not tested.

Test status: tested in the emulator (start and no reload). The reload after a sync is not tested on a real iPod.
