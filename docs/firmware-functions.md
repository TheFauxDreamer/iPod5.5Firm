# Firmware functions (Ghidra findings)

This document records the parts of RetailOS 1.3 that the research identified. It gives the method, the tools, and tables of functions, vtables, RAM addresses, hardware registers and resource IDs. To search for new results, use [ghidra-guide.md](ghidra-guide.md).

All addresses are osos offsets. In the Ghidra project of this research, the base address is 0x0. Thus a Ghidra address is the same as an osos offset. Refer to [The address rule](README.md#the-address-rule).

A name in this document is a name that the research gave. RetailOS has no symbols. The names `FUN_xxxxxxxx` and `DAT_xxxxxxxx` are the automatic Ghidra names.

## Confidence

Each fact has one of these sources. The tables give the source in the "Evidence" column where it is important.

| Source | Meaning |
|---|---|
| Static | Ghidra decompiler output or a disassembly. |
| Emulator | A measurement in the instrumented emulator: a marker, a register record, a write watch or an event log. |
| Patch | A patch that uses the fact operates in the emulator. |
| Real iPod | A test on the real iPod 5.5G of the owner. |
| External | Rockbox, iPodWizard, libgpod or rockpod source code or documents. |

A fact with only a static source can be wrong. Test a patch in the emulator before you trust it.

## The method

The research uses two methods together:

1. **Static analysis.** Ghidra decompiles the functions. The script `CallerTree.java` finds the callers of a function.
2. **Dynamic analysis.** The instrumented emulator runs the firmware. It records which code runs, the register values and the writes to the hardware.

A typical sequence:

1. Record a histogram of the code (`IPODFW_PROFILE=1`, `hist` command) for two conditions, for example a list with and without a scroll.
2. Compare the two histograms. The blocks that run in only one condition belong to the feature.
3. Decompile the functions of those blocks in Ghidra.
4. Record the registers at a candidate address (`IPODFW_REGS_AT`, `regs` command) to find the arguments.
5. Add markers (`IPODFW_MARK_AT`) to find the sequence of the calls and their time.
6. Write a patch. Test it in the emulator.

## The tools

| Tool | Location | Function |
|---|---|---|
| Ghidra 12.1.4 | `~/Library/Application Support/iPodFirm/tools/ghidra_12.1.4_PUBLIC/` | Disassembler and decompiler. |
| Temurin JDK 21 | `~/Library/Application Support/iPodFirm/tools/jdk-21.0.12.1+1/` | Java runtime for Ghidra. |
| Ghidra project `osos13` | `~/Library/Application Support/iPodFirm/re/ghidra-project/` | The analyzed osos 1.3, base address 0x0. |
| [DecompileAt.java](../re/ghidra-scripts/DecompileAt.java) | `re/ghidra-scripts/` | Writes the C code, the callers and the callees of the functions at the given addresses. If no function contains an address, it makes a function at the nearest `stmdb sp!, {..., lr}` before the address. |
| [DecompileAll.java](../re/ghidra-scripts/DecompileAll.java) | `re/ghidra-scripts/` | Writes the C code of every function of the program to one file. The file has one block for each function. The block starts with a line that has the address and the name. |
| [decompile-all.sh](../re/decompile-all.sh) | `re/` | Decompiles the whole image `osos` with REA and with Ghidra. It writes the C code and the index of the functions. |
| [decompile-with-strings.sh](../re/decompile-with-strings.sh) | `re/` | Decompiles the whole image `osos` and makes the map of the strings. It gives the words that hold the address of a string the type of a pointer. The decompiler then names every string that a function uses. |
| [DefineStringPointers.java](../re/ghidra-scripts/DefineStringPointers.java) | `re/ghidra-scripts/` | Gives the type of a pointer to every word of the image that holds the address of a string. |
| [DecompileWithStrings.java](../re/ghidra-scripts/DecompileWithStrings.java) | `re/ghidra-scripts/` | Writes the C code of every function. The C code has the name of every string that the function uses. |
| [make-string-map.py](../re/make-string-map.py) | `re/` | Makes the map of the strings from a file of decompiled C code and from the image. The map has the name and the group of each function. |
| [make-function-index.py](../re/make-function-index.py) | `re/` | Makes the table of the functions from a file of decompiled C code. The table has the address, the name, the number of lines, the number of bytes and the number of calls of each function. |
| [make-systems-state.py](../re/make-systems-state.py) | `re/` | Makes the table of the state of the research of each system. The table has the number of the parts, the number of the parts that a note names, the note that gives the full research of the system and the other notes. |
| [CallerTree.java](../re/ghidra-scripts/CallerTree.java) | `re/ghidra-scripts/` | Writes the caller tree of functions to a given depth. |
| [SetArmOptions.java](../re/ghidra-scripts/SetArmOptions.java) | `re/ghidra-scripts/` | Pre-script. Turns on "ARM Aggressive Instruction Finder" for the first analysis. |
| `FindXrefs.java`, `FindConstant.java`, `FindBytes.java`, `ListVtable.java`, `MakeSignature.java` | `re/ghidra-scripts/` | Search scripts. Refer to [ghidra-guide.md](ghidra-guide.md#2-the-scripts). |
| [DumpCode.java](../re/ghidra-scripts/DumpCode.java) | `re/ghidra-scripts/` | Writes the instructions of the functions at the given addresses, one line per instruction. With `--range`, it writes the instructions of a range of addresses. Use it when the decompiler does not give the function. |
| [find-pattern.py](../re/find-pattern.py) | `re/` | Finds a byte pattern in a raw file without Ghidra. |
| Instrumented emulator | `~/Library/Application Support/iPodFirm/emulator-src/target/release/ipod-emulator` | The emulator with the iPodFirm instrumentation patch. Refer to [re/emulator.md](../re/emulator.md). |
| `ipodfw.emucontrol` | [src/ipodfw/emucontrol.py](../src/ipodfw/emucontrol.py) | Python control of the emulator socket. |
| REA | `/tmp/rea` | The tool for the analysis. It has a provider for Ghidra. Refer to the note [../re/retailos-decompile.md](../re/retailos-decompile.md). |

The tools are not in the repository. The Ghidra download does not include the native decompiler for Apple silicon. To build it:

1. Run `support/gradle/gradlew buildNatives` in the Ghidra folder.
2. Copy `build/os/mac_arm_64/*` to `os/mac_arm_64/` in each module.

## Load osos into Ghidra

1. Get osos from the Apple firmware:

   ```sh
   uv run ipodfw extract iPod_25.1.3.ipsw -o fw13.bin
   uv run python -c "from ipodfw.partition import FirmwarePartition as F; open('osos-1.3.bin','wb').write(F(open('fw13.bin','rb').read()).image('osos'))"
   ```

2. In Ghidra, import `osos-1.3.bin` as "Raw Binary".
3. Set the language to `ARM:LE:32:v4t`.
4. Set the base address to 0x0.
5. Run the analysis with the pre-script `SetArmOptions.java`.

CAUTION: Do not commit `osos-1.3.bin`, `fw13.bin` or the Ghidra project. They contain Apple code.

## Run a script without a window

```sh
T="$HOME/Library/Application Support/iPodFirm/tools"
R="$HOME/Library/Application Support/iPodFirm/re"
JAVA_HOME="$T/jdk-21.0.12.1+1/Contents/Home" \
  "$T/ghidra_12.1.4_PUBLIC/support/analyzeHeadless" "$R/ghidra-project" osos13 \
  -process osos-1.3.bin -noanalysis -readOnly \
  -scriptPath re/ghidra-scripts -postScript DecompileAt.java OUT.c 0x135b2c 0x223420
```

For a caller tree, use `-postScript CallerTree.java OUT.txt DEPTH ADDRESS ...`.

## The architecture of RetailOS

- The CPU is the ARM7TDMI of the PortalPlayer PP5022 (ARMv4T). The code uses the ARM state.
- The boot loader in the NOR flash loads osos to SDRAM at physical address 0x10000000. The CPU addresses of the code are equal to the osos offsets. The research did not examine how the memory controller does this.
- The user interface has two layers:
  - Native ARM code draws the screens.
  - Compiled JavaScript in the resource `TCmd` 9088 controls the behaviour.
- The JavaScript engine is a version of Mozilla SpiderMonkey (JavaScript 1.5). Refer to [The JavaScript engine](#the-javascript-engine).
- The screens are objects with vtables (C++ classes). A vtable word hook changes the method for all objects of a class.

## Functions

### The whole image

The research of 21 October 2026 decompiled the whole image `osos` of RetailOS
1.3 with REA and with Ghidra. The research gives 14,411 functions. The research
failed for 0 functions. The C code has 551,459 lines.

| The item | The value |
|---|---|
| The functions | 14,411 |
| The C code | 551,459 lines. 13,378,201 bytes. |
| The range of the addresses | 0x100000f0 to 0x10733b64 |
| The median size of a function | 24 lines of C code |
| The functions under 50 lines | 11,902 |
| The functions over 500 lines | 31 |
| The C code and the index | `~/Library/Application Support/iPodFirm/re/retailos-1.3-decompiled/` |

The research confirmed the addresses of the other notes. Refer to [../re/retailos-decompile.md](../re/retailos-decompile.md).

> CAUTION: The image has no symbols. The names of the functions are `FUN_` and
> the address. The C code of a function with many paths has the name
> `extraout_r1` many times. The logic of the code is still correct.

### The map of the strings

The research of 22 October 2026 made the map of the strings of the image
`osos`. The map gives the name of each function and the group of each
function. The name comes from the strings that the function uses.

| The item | The value |
|---|---|
| The functions of the image | 14,411 |
| The functions with a string | 382 |
| The functions with a name | 380 |
| The different strings | 841 |
| The groups | Files and storage 60. System and services 31. Tools and build 29. Music and audio 27. Video and photo 26. DRM and FairPlay 1. |
| The files of the map | `~/Library/Application Support/iPodFirm/re/retailos-1.3-decompiled/` |

The function `FUN_10175c74` uses 83 strings. These strings are the names of
the atoms of the files of the DRM. The list has `AppleDRM`, `AppleLossless`,
`AppleVideoDRM`, `FireWireGUID` and `FireWireVersion`.

Refer to [../re/retailos-decompile.md](../re/retailos-decompile.md) for the
method, the limits and the whole table.

### Resources and strings

| Address | Function | Evidence |
|---|---|---|
| 0x21f254 | General resource lookup (provider, type, id). All resource and string lookups pass here, also the virtual calls. The first instruction is `push {r3-r7, lr}`. | Static, Patch (`dark-mode`) |
| 0x21f3dc | Lookup of any type. Continues in 0x21f254. | Static |
| 0x21f408 | Lookup of a `BMap`. Continues in 0x21f254. | Static |
| 0x21f418 | Lookup of a `Str ` (table, id). | Static, Patch |
| 0x21f3b8 | Returns the string table. | Patch |
| 0x192ca8 | Returns the language key: the settings key 0x6062, value 0x6063 (English) to 0x607b. The default is 0x6063. It reads address 0 + 0xa8 if the settings object does not exist, thus test `0x1d3050(0x6000)` first. Refer to [re/languages.md](../re/languages.md). | Static |
| 0x1d3050 | Finds an object by its key in the object map, for example 0x6000 (the settings object). Returns 0 if the object does not exist. | Static |
| 0x190a9c, 0x190a84 | 0x190a9c finds the language record of the current key in the table at 0x2a9a74. 0x190a84 returns its four-character code. | Static |
| 0x140404 | At the start: makes the provider of the main block and one provider for each of the 24 language blocks (0x1406fc). | Static |
| 0x14047c | Registers each language provider with its four-character code (method + 0x74 of the language manager). | Static |
| 0x1529d4 | Method + 0x6c of the language manager: selects the language with a code (0x1aea64 writes the code to + 0x3c and the provider to + 0x40). Then it reads the date formats (`LDTm` 128). | Static |
| 0x1528cc, 0x1ae9d4 | Method + 0x5c of the language manager: the lookup. It asks the current provider (+ 0x40). If the provider has no resource, the lookup continues in the main block. ID 0xa9 is the 24-hour clock flag. | Static |
| 0xc60ec | Finds an image in the firmware directory by type and ID. Reads the sector with `]ih[`, then the directory. | Static |
| 0xfc3bc | Calls 0xc60ec. Called with `crsr` at 0xaf548 and 0x1afe44. | Static |

### The user interface: views and labels

| Address | Function | Evidence |
|---|---|---|
| 0x244924 | Draw method of the general label class (type 0x1580). Arguments: view, text, a3. | Emulator, Patch (`album-art`) |
| 0x1bb260 | Draw method of the list-row label class (type 0x3180). Scrolls a long title from a cached image of the text. One album row (0x1bb260 or 0x244924) takes approximately 2 ms in the emulator and approximately 7 ms on the real iPod (refer to [../re/album-art-v2.md](../re/album-art-v2.md)). | Emulator, Patch |
| 0x255ac4 | Gets the rectangle of a view: {top, left, bottom, right}. | Patch |
| 0x21a27c | Prepares the graphics context of a view: origin and clip. | Patch |
| 0x21a4f4 | Makes a view from a View resource. Copies the positions, heights and highlight colours of the elements. | Static |
| 0x17def4 | Makes the child views. | Static |
| 0x2445d4 | Method 0xd0 of a view: applies a layout again, but only the text styles (calls 0x243f60). | Static |
| 0x1bccfc | Loads picture 24351 for the rating row. | Static |
| 0x1bcd44 | Repeats a picture across a row. | Static |
| 0x122b28 | Calls the JavaScript interpreter from the list code. | Emulator |

### Draw functions

| Address | Function | Evidence |
|---|---|---|
| 0x2106e4 | Sets the colour of the graphics context: 4 bytes R, G, B, A. | Patch |
| 0x210290 | Sets the draw mode. Apple code uses 0, 1, 8, 32, 33 and 34. Mode 0 replaces the pixels. Mode 1 darkens. | Patch, Emulator |
| 0x211a00 | Fills a rectangle. Adds the gc origin and calls 0xc01a4 with the bitmap of the gc. | Patch, Static |
| 0xc01a4 | (bitmap descriptor, rect, colour, mode): fills a rectangle in a bitmap. Clips with the bounds of the bitmap, then marks the damage (0xe944c). | Static |
| 0x210114 | Blit (gc, source gc, source rect, target rect). Adds the origins of the two gcs and calls 0x1216a0 with the clip at gc + 0x34. The row label draws its cached text images with it. | Static, Patch (`album-art`) |
| 0x1216a0 | The blit core (source descriptor, target descriptor, source rect, target rect, colour, colour 2, mode, clip). If the two formats agree (mask 0xdfff) and the mode is 0, it copies the pixels. | Static |
| 0x210638 | Sets a new gc to its start values (0x44 bytes). | Static |
| 0x211a70 | (gc, bitmap): sets gc + 0x1c to the bitmap and the clip (gc + 0x34) to the bounds at bitmap + 0x98. | Static |
| 0xe442c, 0xe944c | Before and after a draw into a bitmap: call the listeners at descriptor + 0x24, and add the rectangle to the damaged area. | Static |

### The music database in RAM

| Address | Function | Evidence |
|---|---|---|
| 0x9bc6c | Resolves a library reference: type byte 1 is the library, type 2 has it at + 0xc9c. | Static |
| 0x9c838 | (track list, sort, reverse, i): the item at sorted position i. Builds a missing sorted array with 0x1120bc. | Static |
| 0x9cb7c | Example: the title of track i of the list of all tracks. | Static |
| 0x9c9fc | The album name of row i of the Albums list: 0x9eff8(db + 0x138, (library + 0xc60)[i]). | Static, Emulator, Patch (`cover-flow`) |
| 0x9cabc | The artist name of row i of the Artists list (library + 0xc48, pool db + 0xe0). | Static |
| 0x9eff8 | (pool, index, buffer, &length, maximum): copies the UTF-16 text of a pool entry. | Static |
| 0x885ec | Stores a string in a pool. | Static |
| 0x88a00 | (pool, string with a u16 length, &index): stores a string in a pool. The playlist parser stores each playlist name with it (pool at playlist + 0xb4, index at playlist + 0xe0). | Static, Emulator |
| 0x93ff0 | (db, …, is master, …, &playlist): makes a playlist object for a mhyp (a track list: root at + 0x28). The master playlist goes to db + 0x30. Calls 0x1012b8 and 0xb6b54. | Static, Emulator |
| 0x1012b8 | (playlist): sets up the name pool at playlist + 0xb4 (0x947f8) and the root node at + 0x28 (0xd1df0). | Static |
| 0xb6b54 | (db, playlist): adds the playlist to the list of all playlists (db + 0x2c, 0x88ef0), adds 1 to db + 0x28 and writes db to playlist + 0x0c. | Static, Emulator |
| 0x88ef0 | (head, node): adds a node at the end of a singly linked list. The next node is at node + 0x00. | Static |
| 0x88944 | (playlist, track, cursor): makes an item for a track (0xd1df0; item + 0x20 = track) and links it (0xd6614). | Static, Emulator |

The list of all playlists: db (library + 0xcf8) + 0x2c, linked by playlist + 0x00, count at db + 0x28. It also has the master playlist, "New Voice Memos", a playlist with no name and On-The-Go (library + 0xce0). The items of a playlist: root (playlist + 0x28) + 0x20, then item + 0x08; the count is root + 0x32 (u16). Emulator, 27 October 2026. Refer to [../re/playlist-art.md](../re/playlist-art.md).
| 0x10a15c | Converts an mhod-52 sort type to a slot (album 4 → 6). | Static |
| 0x1e804c | The property method of the main provider (class 0x670f54) for the music screens. | Static |
| 0x21f254 | (provider, type, ID): asks the provider and its parents for a property (vtable + 0x5c). | Static |

### Text drawing

| Address | Function | Evidence |
|---|---|---|
| 0x2438bc | Draws the text of a label (called by 0x244924). | Static |
| 0x2115a4 | Measures a UTF-8 text (gc, text, width). | Static |
| 0x2106ec, 0x2113c0 | Draw a UTF-8 text into a rectangle with the font of the graphics context. | Static |

A label draws in the rectangle at view + 0x58 (top, left, bottom, right in its parent). The `cover-flow` patch draws its caption with the album label (element 0x6421) of the list's template cell: it attaches the label to the top view, sets the rectangle, calls 0x244924, and puts the fields back. The label draws at the left with the font and the colour of the list rows. (Patch)

### Artwork

| Address | Function | Evidence |
|---|---|---|
| 0xa1ff0 | Opens `iPod_Control\Artwork\ArtworkDB` when the music database loads (0xb4a64). | Static |
| 0x205cfc, 0x205db4 | Starts the task `ArtworkLoadTask`, and its task function: a request queue, an image cache and reference-counted image objects. | Static |
| 0x88094 | Writes `Thumbs\F%d_%d.ithmb` of the Photos database. | Static |

### The display

The firmware draws into a CPU framebuffer and sends the dirty rows to the BCM co-processor. Refer to [../re/cover-flow.md](../re/cover-flow.md#the-screen).

| Address | Function | Evidence |
|---|---|---|
| 0x1647c0 | Returns the display server (RAM 0x10882c3c). | Static, Emulator |
| 0x164610 | Returns layer N (server, N): server + 0x110 + N × 0x90, for N < 11. | Static |
| 0x164878 | Binds layer N (server, N). Waits while server + 0x6c4 is not 0, then writes the layer to server + 0x6c4. | Static, Patch (`cover-flow`) |
| 0x164d0c | Task: after each flush, sends the update to the BCM and writes 0 to server + 0x6c4. | Static |
| 0x1650f8 | Flush (server, N). If layer N is bound, calls the present 0x164f44 with the layer and server + 0x6b0. | Static, Patch |
| 0x164f44 | Present: sends the dirty rows of the CPU framebuffer to the BCM surface and changes the two surfaces. | Static, Emulator |
| 0x17ef98 | Damage callback (unused, rectangle, 0): sets the dirty rows. If the byte at RAM 0x1081ec54 is not 0, it binds the layer first. Registered at the start by 0x17eeb0 from the literal 0x17ef8c. | Static, Patch |
| 0x169718 | Example of a full update: bind, set the update, flush. | Static |
| 0x0c9a84, 0x0c9b58 | Lock and unlock a mutex (the display uses server + 0x6c8). | Static, Patch |
| 0x21ac04 | Marks the rectangle of a view as damaged, so that the firmware draws it again. | Static, Patch |

### Text

| Address | Function | Evidence |
|---|---|---|
| 0x2234dc | Reads one UTF-8 character and returns a UTF-16 value. | Static |
| 0x223420 | Converts a UTF-8 string to a new UTF-16 string. | Static |
| 0x224414 | Length of a UTF-8 string. | Static |
| 0x224278 | Next character. | Static |
| 0x224190 | Text function for the database strings. Runs only for the Albums list. | Emulator |
| 0x092948 | Copies a C string into a Pascal string (string, buffer, size). | Static, Patch (version) |
| 0x0934c4 | Copies a Pascal string into a string object. | Static, Patch |
| 0x09ee70 | Makes the version text of the About screen. `mov r1, #1` at 0x9ee90 and `mov r2, #0x30` at 0x9ee94. | Static, Emulator |
| 0x188d94 | Adds a stage text ("d", "a", "b", "fc") to a version (table 0x4fc298). | Static |

### Memory and files

| Address | Function | Evidence |
|---|---|---|
| 0x25a974 | Allocates memory from the heap object at *(0x1081da00): calls 0x1ac4ec with flag 2. | Static, Patch |
| 0x1ac4ec | (heap, size, clear, flag, old block, copy, quiet): the allocator of the heap. A block has a header word (size, bits 0–1 and 30–31 are flags). It subtracts merged free blocks from heap + 0x00 and adds 1 to heap + 0x08. | Static, Emulator |
| 0x0a07b4 | Calculates the heap region: start = struct + 0x28 AND 0xfbffffff, size = (struct + 0x20 − struct + 0x24) AND 0x3ffffff. Writes them to 0x10883614 + 0x1b4 and + 0x1b8. 0xc2bbc calls it. | Static |
| 0x10b190 | Adds the RAM to the heap: calls 0xdf0c0, then 0xd2e2c. | Static |
| 0x0df0c0 | Rounds the end of the RAM region down to 1 MB and subtracts 1 MB (the MMAP window at 0x18000000). | Static |
| 0x0d2e2c | Adds a region to the heap through 0x1ac448. A heap has a maximum of 10 regions. | Static |
| 0x0c2e0c | Makes the heap object at 0x10870154 when the firmware first needs it (0x1aca4c, then 0x1ac944). | Static |
| 0x0c7444 | Gives the free bytes of the heap. The patch `playback-log` uses it. | Static, Patch |
| 0x0c7518 | (size, alignment): an allocator. Calls 0xc2e0c, then 0x1ac324 with the heap. 0xa8180 (`mov r1, #4`) jumps to it. The patch `playback-log` hooks its first instruction. Refer to [../re/playback-log.md](../re/playback-log.md#the-memory). | Static, Patch |
| 0x11ca20 | (size, flags): an allocator. Calls 0xc2e0c, then 0x1ac9b4 with the heap. 0x25a974 (`mov r1, #2`) and 0xa8178 (`mov r1, #4`) jump to it. The patch `playback-log` hooks its first instruction. | Static, Patch |
| 0x0a96c0 | The block allocator of the track objects (slab at db + 0x38: element size at + 0x04, count for each chunk at + 0x08). Calls 0xa8e8c. A chunk is count × size + 0x24 bytes from 0xa8178. A track object is 272 bytes, 100 in each chunk. | Static, Emulator |
| 0x25a944 | Allocates memory (used by 0x223420). | Static |
| 0x25a8e4 | Frees memory to the same pool. | Patch |
| 0x07ccd0 | Fills memory with zeros (pointer, size). | Patch |
| 0x07cd6c | Copies a C string. | Patch |
| 0x08f38c | Opens a file for read. Arguments: path record (0x108 bytes, path at +4), file handle (0x30 bytes), 0, mode `'data'`. Paths use backslashes. | Patch |
| 0x08f3f8 | Opens a file for read and write (access 3). Makes the file if it does not exist. | Patch |
| 0x08f464 | Reads from a file (handle, pointer to length, buffer). | Patch |
| 0x08f6f4 | Writes to a file (handle, pointer to length, buffer). | Patch |
| 0x08f5c4 | Sets the file position. The 64-bit position is in r2:r3. | Patch |
| 0x08f184 | Closes a file. Writes the buffer to the disk. | Patch |
| 0x0e468c | (path record, type, folder, name): joins the folder and the name into the path record (0xc6994), deletes an old file (0xa4770) and makes an empty file (0xa449c with mode 2, then 0xa4400). The firmware uses it for `OTGPlaylistInfo` (type `'itun'`). The `up-next` patch uses it for its file; after a restart in the emulator, the value was still there. | Static, Emulator, Patch |
| 0xb4a64 | Loads the music database from `iPod_Control\iTunes\iTunesDB`. Runs at the start and after each USB session. At 0xb4ad4 it adds the usage-log event 0xf ("Exit Disk Mode"). It measures the free heap before and after each load and writes the events 0x16 "Music Database Size", 0x17 "Photo Database Size" and 0x18 "Artwork Database Size". If the load fails, it tries `System\Control\iTunes\iTunesDB`, then makes an empty database (0xa9348). Refer to [../re/ram-limit.md](../re/ram-limit.md). | Static, Patch (`album-art`) |
| 0xa2310 | Makes the music database object and calls 0xb4a64 (at 0xa23fc). | Static |
| 0x1edb9c | Loads the music database again (`blne 0xb4a64` at 0x1ed2d0) if the flag at +0x489 is 0. | Static |
| 0x213c5c | Adds an event to the usage log (log, event, value). | Static, Patch |
| 0x213cd4 | Gives the name of a usage-log event. 0xe is "Enter Disk Mode", 0xf is "Exit Disk Mode". Only 0xb4ff8 (in the database reload 0xb4fe4) writes the event 0xe, and only 0xb4ad4 (in the first load 0xb4a64) writes the event 0xf. This comes from a scan of all `bl` to 0x213c5c with `mov r1, #0xe` or `#0xf` before them (27 October 2026). | Static |

### The start and the RAM size

RetailOS does not test the RAM. It reads the size from the SysInfo block of the boot loader. Refer to [../re/ram-limit.md](../re/ram-limit.md).

| Address | Function | Evidence |
|---|---|---|
| 0x0013bc | The start code. Finds the SysInfo block: the tag 'SysI' (0x53797349) at 0x4001ff18, then a pointer. | Static |
| 0x0013e8 | `ldr r3, [r0, #0xe0]` (`e0 30 90 e5`): reads the SDRAM size from SysInfo + 0xe0. `mov r3, #0x2000000` (`02 34 a0 e3`) here makes a 32 MB heap in the emulator. | Static, Emulator |
| 0x000e6c | Converts the size to a code with the size table at 0x16d8 (0, 0x80000 … 0x8000000). | Static |
| 0x281224 | Copies the SysInfo block (at most 0xf8 bytes) to 0x108710dc and sets the pointer of 0x2827b8 through 0x282800. The start code calls it at 0x2bc. Refer to [re/search-5g.md](../re/search-5g.md#how-the-value-gets-into-the-firmware). | Static, Emulator |
| 0x2827b8 | Returns the SysInfo pointer at 0x1081df80 (0x108710dc). The fallback 0x10882048 applies only if the pointer is 0. | Static, Emulator |
| 0x09d9d0 | Gives the RAM size: SysInfo + 0xe0, from the copy at 0x108710dc. 0x947f8 compares it with 0x3ffffff. The patch `playback-log` uses it. | Static, Patch |
| 0x000df8 | Adds the sizes of the four banks and writes the RAM top to struct + 0x20. | Static |
| 0x000c90 | Sets the image region (8 MB) and the data region (from 0x10800000, length 0x20e294). | Static |
| 0x001658 | Copies the struct (0x90 bytes) from IRAM 0x40006000 to 0x14983060. | Static |

### Settings, sleep and restart

| Address | Function | Evidence |
|---|---|---|
| 0x190b00 | "Get" method of the settings object (vtable slot 0x66c94c). Operations are four-character codes: `prID`, `Str `, `Ui32`. The value text of the Shuffle item (key 0x6057) is the string `0x6058 + mode` (Off, Songs, Albums). The string 0x605b exists in no language. The label of the item is the string −135 (0xff79), "Shuffle". 0x6057 is only the key. | Static, Patch |
| 0x1919d8 | "Set" method of the settings object (vtable slot 0x66c950). Shuffle item (key 0x6057): Select adds 1 to the cached mode at `controller + 0x1c` and wraps after 2 (`cmp r0, #2` at 0x191e9c). Then it calls 0xb3a04 at 0x191eb0. | Static, Patch |
| 0xb2e74, 0x9b240 | Setter and getter of the backlight setting (settings +0xaf8). | Static |
| 0x193b90 | Copies a setting and posts event 0x60000006 when it changes. | Static |
| 0x1eb65c | Native method: writes the backlight seconds to the application object +0x444. | Static, Emulator |
| 0x1ee8b8 | Saves the settings and the database, as before a sleep. | Static, Patch |
| 0x0bc094 | Saves all (the database, the settings with 0xbbf1c, and other data). Called by 0x1ee8b8, 0xb4fe4 and 0x248440. | Static |
| 0x0bbf1c | (settings): writes the settings only if the byte "changed" (+0xb74) is set. Called by 0xbc094 and the sleep sequence 0x1ee8d0. A restart with Menu+Select runs no save, thus the changes since the last sleep are lost (real iPod, 16 October 2026, also for the Apple row Songs). The write itself is 0xbbdf8. | Static, Emulator, Real iPod |
| 0x0af698 | (settings): makes the settings at a start. Calls the defaults 0xf3dc0 and the load 0xe1b64 on `settings + 8`, then updates old file versions (current version 0x39). Writes the maximum volume to `+0xb78`. | Static |
| 0x0e1b64 | (block): clears the block and reads `/iPod_Control/Device/Preferences` into it, a maximum of 0xb6c bytes, with no check. A field at `settings + X` is at file offset X − 8, for example `+0x93` at 0x8b. | Static, Emulator |
| 0x0f3dc0 | (block): the default settings. Clears 0xb6c bytes, then sets some fields. Version 0x39. | Static |
| 0x1a0120, 0x19ff0c, 0x19ff6c | 0x1a0120 returns the memory cache manager. 0x19ff0c(manager) sets + 0x44 = 1 and sends the event 10 ("give back the memory", 0x19f9b0) to its users until the count + 0x6c is 0. 0x19ff6c sends the event 5 at the end. 0x19fd0c (a new block) sets + 0x44 = 0. Apple calls 0x19ff0c only in 0x1ed828 (0x1ed918 then calls 0x19ff6c) and before the sleep (0xb43dc). The only caller of 0x1ed828 is the `bl` at 0x1eea00 in the sleep sequence 0x1ee8d0 (Ghidra, 27 October 2026). An earlier version of this table said "before the disk mode". No path from the disk mode start to 0x1ed828 is known. Earlier this table called 0x19ff0c a disk cache flush; that was not correct. The USB host probe called it at each log write until version 1.18 (the probable cause of the missing Now Playing art). | Static, Emulator, Real iPod |
| 0x1ee8d0 | Sleep sequence: saves, writes the cache (0x1ed828, 0x19ff0c), then calls the sleep method. Does not sleep if external power is found. | Static, Emulator |
| 0x1d9344, 0x1dfe18 | The only call of the sleep sequence 0x1ee8d0 (in 0x1d8cd0) and the only call of the sleep function 0xb43dc (in the sleep method 0x1dfdd4). The patch `diagnostic-log` hooks both. | Static, Patch |
| 0x1ecc8c | External-power test, from saved copies of the power pins (vtable offset 0xb4 → 0x9e664). | Static |
| 0x265698 | Reads the power source pins. | Static |
| 0x1d83fc | Sleep item handler: backlight off (0xb4638), start the idle timer (controller + 0x48, 500 ms). | Static, Emulator |
| 0x1e8cd4 | App command 7. Calls the Sleep item handler at 0x1e8ce8. | Static |
| 0x1d8a40 | Idle timer handler. Sleeps only if the gate 0x1d938c passes. | Static, Emulator |
| 0x1d938c, 0x1d8d9c, 0x1d8444, 0x1d8670, 0x1d8718 | The sleep gate. Refer to [re/sleep.md](../re/sleep.md). | Static, Emulator |
| 0x1d8cd0 | Timer handler. Its part at 0x1d9308 calls 0x1ee8d0 and, after the wake, 0x1d813c. | Static, Patch |
| 0x1dfdd4 | Sleep method (vtable 0x670720, offset 0x70). Calls 0xb43dc. | Static |
| 0xb43dc | Sleep function: display off (0xb7c64(0)), keep-awake message type 4, power mode 3 or 2 (0x2823bc). After the wake it ends with `bl 0x1b9118` at 0xb45f4. | Static, Emulator |
| 0x388 | Hibernation dump handler in the boot block. The literals at 0x534 and 0x538 hold `!ATA` and `ebih`. The handler scans the directory through boot-ROM services (0x350 → 0x40003828, reads 0x40003260, header write 0x40003400, dump write 0x40001a34). At 0x468 it checks the entry length against the value + 0x800 (the dump is 64 MB of RAM plus the 0x800-byte header). It writes a dump only when the directory already has an `ebih` entry. Nothing in osos creates the entry. Refer to [re/hibernation-restore.md](../re/hibernation-restore.md). | Static, Real iPod |
| 0x2823bc | Power-state entry (modes 1, 2, 3, 5). | Static |
| 0x1c1f5c | Returns the voice recorder object (component 0x3d00). Byte +0x66 is 1 during a recording. | Static |
| 0x151c98 | Stops a timer. | Patch |
| 0x151c24 | Sets the interval of a timer in ms (timer, ms). Stops the timer first. | Static, Patch (`cover-flow`) |
| 0x151694 | Starts a timer. Its event goes to the owner of the timer. | Static, Patch (`cover-flow`) |
| 0x13d7c8 | Initializes a timer (owner, timer, 0, 0). The browse-list constructor 0x23b97c calls it for its two timers. | Static |
| 0x23b97c | Constructor of a browse list. Makes the timer at list + 0xcc (100 ms, the blink of the selected row) and the timer at list + 0x104 (2000 ms). | Static |
| 0x094e08 | Keep-awake message type 4 ("sleep now"). Also used before a restart. | Static, Patch |
| 0x001630 | Restart: writes 4 to `DEV_RS` (0x60006004). | Static, Emulator |

### Volume and region

Refer to [re/volume-limit.md](../re/volume-limit.md).

| Address | Function | Evidence |
|---|---|---|
| 0xa0348 | Returns bit 0 of the flags (device information +0x94): the EU volume limit. The patch `volume-unlimit` changes it. | Static, External (iPodWizard) |
| 0x9f0f8 | Returns bits 1–2 of the flags (`flags & 6`). Only caller: 0x9bd88. Not the volume limit. | Static |
| 0x9e958 | Returns the region code (device information `+0x92 & 0xff3f`). | Static |
| 0x9bd88, 0x9bcd0 | Default values for settings +0xb3a and +0xb4e, from the region code. | Static |
| 0xaf698 | Settings load. Writes the maximum volume to +0xb78: 0xd8 with the EU limit, 0x100 without it. | Static |
| 0x88ff8 | Output volume: `level × maximum / 100`, with the maximum from +0xb78. The result is linear: level 1 gives 2 of 256. | Static |
| 0xb4078 | (player, output volume): calls 0x116d84 with the balance 0x32 and the flag 1, then 0xbb0f4. | Static |
| 0x116d84 | (object, output volume, balance, flag): limits the output volume to the result of 0x9d99c, keeps it at +0x276c, and keeps the balance at +0x2774. Sends the gain to 0xec4ac or 0x14499c. | Static |
| 0xd1eb0 | (object): calculates 2 gains from the output volume and the balance: one in the low 16 bits and one in the high 16 bits. The limit before the balance is 0x200. | Static |
| 0xec4ac | (object, gains): keeps the gains at +0x230 and sends the high gain >> 1, with the limit 0x7f, to 0x14499c. | Static |
| 0x1a3254 | iAP command handler. Case 0x24 replies 0x25 with the bit 0x1000000 if the EU limit is set. | Static |

### User events

| Address | Function | Evidence |
|---|---|---|
| 0x1d2ee8 | (ID): posts an event of type 8 with the ID (0x2141fc, 0x2141a0, 0x13d6d4). Native code asks the script for a screen with it. | Static |
| 0x1d81cc | UI event handler. Runs in the UI task for each button and wheel event. It adds 1 to the byte UI + 0x44 at a key push (type 4) and subtracts 1 at the release (type 7). `playlist-folders` hooks its first instruction (`push {r4-r8, lr}`). | Static, Emulator, Patch |
| 0x1d813c | Starts the idle timer again and turns the display on. Called at 0x1d8344 for a button event, not for the wheel events 0x10 and 0x1c. | Emulator |
| 0x1d8264 | UI event handler part: calls 0x94bbc(4) and then 0x94d80(4, 3000) while the storage is on. | Static |
| 0x1d8570 | 5000 ms timer of key 0x6e (a long push of Play). Posts screen 0x63f2. The handler 0x1d81cc calls it at 0x1d8260 for each event; the code after the call does not use r0. | Static, Patch (`usb-host-probe`) |
| 0x283e10 | Backlight function. Only the sleep and wake paths call it. | Static |
| 0x13d524 | Event dispatcher (event, target). Gives the event to the filter objects (slot +0x34), then to the target or to the focused object and its parents (slot +0x30), then deletes it (event slot +4). | Static, Emulator |
| 0x23b704 | Event method of the browse lists (class 0x677290 and two other classes). Handles the push (type 4) and the wheel (type 0xf). A wheel event has +0x0c = +1 or −1 for each step, and 0 at the end of a movement. In the Albums list, `view_invalidate` (0x21ac04) on the list at the end event draws the visible rows again. The real wheel sends the end event rarely (5 in approximately 22 s). The lists also get type 0xd: approximately each 240 ms in the emulator, but only each 3–4 s on the real iPod. A timer event (type 9) of the timer at list + 0xcc: if the list is visible, it calls method +0x184 with 1 or 0 by turns, decreases the byte at list + 0xf8 and starts the timer again until the byte is 0 (a blink of the selected row). A count of 0 becomes 255. If the list is not visible, it calls +0x184 with 1 and sets the count to 0. | Emulator, Real iPod, Patch (`cover-flow`, `album-art`) |
| 0x23a04c | Method +0x138 of a browse list: sets the selected row and posts the property event "LstS". | Static |
| 0x1d3348 | Event method of the application object (class 0x66a510). Sends events to handlers in maps, for example 0x1d81cc. | Static, Emulator |
| 0x1d8aa4 | Key actions of the UI handler (called for the types 4–7). | Static |
| 0xa69dc | The click of the lists. Reads the Clicker setting (RAM 0x1081d9c4): value 1 speaker (piezo message), value 2 headphones (audio click 0x1b9168). The test of value 2 is at 0xa6a90. No arguments. Refer to [../re/clicker.md](../re/clicker.md). | Static, Emulator, Patch (`cover-flow`, `click-speaker-only`) |
| 0x1b9168 | Plays a sound on the audio path (the click; also called from 0x88aec and 0x26a560). Then, if the byte at 0x10882440 + 0x3e has bit 0, the piezo tone 0xcd430(0x55, 3000) at 0x1b91fc. | Static, Emulator |

The first argument of 0x1d81cc and of 0x1d813c is the UI object (0x13e358a4 in the emulator). It is not the application object.

Key events and key codes (emulator, refer to [../re/cover-flow.md](../re/cover-flow.md#the-events)):

| Type | Meaning |
|---|---|
| 4 | Key push. The UI handler 0x1d81cc gets it first, then the focused list and its parents. |
| 5 | Key repeat |
| 6 | Key held for 0.5 s. Only the UI handler gets it. |
| 7 | Key release. Only the UI handler gets it. The firmware acts on Menu at type 6 or 7. |
| 0xf | Wheel step. Event + 0xc is +1 or −1, 0 at the end. |

| Key | Code (bits 16–23 of event + 0x10) |
|---|---|
| Select | 0x6f |
| Menu | 0x6e |
| Play/Pause | 0x10 |

### Storage power and keep-awake

| Address | Function | Evidence |
|---|---|---|
| 0x284b0c | Keep-awake task. 45 client slots. When no slot is active, it tells the storage task to sleep. | Static, Emulator |
| 0x284c7c | `ldr r1, [r4, #0x18]`: the time of a type-2 message. | Static, Patch |
| 0x94e6c | Keep-awake type 0: always on (slot, 0). | Static, Patch |
| 0x94bbc | Keep-awake type 1: on if the storage is on. Returns the result. | Static |
| 0x94d80 | Keep-awake type 2: on for r1 ms. Sends r1 + 1. | Static, Patch |
| 0x94d1c | Keep-awake type 3. | Static |
| 0x94c24, 0x94c88 | Keep-awake types 5 and 6. | Static |
| 0x94cec | Returns 1 if any slot is active. | Static, Patch |
| 0x265cc8 | Drive power on (1) or off (0). Apple's `ide_power_enable`. Sets `GPO32_VAL` bit 30 (set = off), `DEV_EN` bit 0x2000000 and the GPIO enables. Waits 4 ms and 10 µs after power on. | Static, Emulator, External (Rockbox) |
| 0x233358 | Drive "set power" method. Argument 1: STANDBY IMMEDIATE, wait, controller off, power off (call at 0x23344c). | Static, Emulator |
| 0x233478 | ATA object set-up. | Static |
| 0x232ec8 | Waits for ready after power on: polls BSY = 0 and DRDY = 1 each 10 ms. After 10 s, power cycle. 21 s in total. | Static |
| 0x142fc0, 0x14316c | ATA commands with a 10 s timeout. | Static |
| 0x142e48 | Sends IDENTIFY (0xEC) into the 512-byte buffer at ATA object + 0x0C, then swaps the bytes of the text fields. Runs one time at start. | Static, Emulator |
| 0x282cf0 | Sets a GPIO pin (pin, value). | Static |
| 0x282870, 0x2828b8 | Busy wait in ms and in µs (`USEC_TIMER`). | Static |
| 0x11c9fc | Task sleep in ms. | Static, Patch |

### The music database

Refer to [re/album-artist.md](../re/album-artist.md). The `album-artists` patch uses 0xd7888, 0xd7e40 (hook at 0xd7ea0), 0xd821c and 0x10db84 ("Patch" in the table below).

| Address | Function | Evidence |
|---|---|---|
| 0x0af930 | Loads iTunesDB. Calls 0xd7888 for the tracks and 0xd6de8 for the playlists. | Static |
| 0x0d7888 | Reads the tracks (mhit) and their strings (mhod). The loader calls it one time for each load (`bl` at 0xafc8c). If the allocation of a track object fails, it returns −0x6c (−108, memFullErr). | Static, Emulator, Patch |
| 0x0d7e40 | The jump on the mhod type. The table of `b` instructions is at 0xd7e48 + 4 × type (types 0 to 31). Type 22 (Album Artist) goes to the skip code 0xd81ec. | Static, Emulator |
| 0x0d7f58 | The code for mhod type 4 (Artist). | Static, Emulator |
| 0x0d821c | The end of the mhod loop body. It examines the result in r5. | Static, Emulator |
| 0x0d6de8 | Reads the playlists. Its mhod strings are only the playlist names. | Static |
| 0x10db84 | Reads an mhod string into a string pool. Arguments: reader, 1, type, pool, slot, 1. | Static, Emulator |
| 0x0f4340 | Reads the string header and the text. Compares the type only with 2 (path). | Static |
| 0x0885ec | Stores a text in a pool (pool, text, length, slot). Writes 0 to the slot first. An empty text gives the index 0. Each track gets its own index, also for the same text: 4000 tracks with 400 album names gave 4000 different Album Artist indexes. Thus compare the texts, not the indexes. | Static, Emulator |
| 0x0907f4 | Updates the artist data of a track. Calls 0x1114dc. | Static, Emulator |
| 0x1114dc | Makes the artist sort key of a track (pool db + 0x10c). | Static |
| 0x0dc6a8 | Skips bytes in the file. | Static |

The mhod types that 0xd7888 keeps, with the pool of each type: 1 title (db + 0xb4), 2 path (0x1179bc), 3 album (+ 0x138), 4 artist (+ 0xe0), 5 genre (+ 0x190), 6 file type (+ 0x1bc), 7 EQ (+ 0x1e8), 8 comment (+ 0x214), 9 category (+ 0x240), 12 composer (+ 0xe0), 13 grouping (+ 0x164), 14 description (+ 0x424), 16 and 17 podcast data, 19 (+ 0x47c), 20 (+ 0x4a8). 0xd81ec skips the types 10, 15, 18, 21, 22, 24, 25 and 27 to 31. Static. Refer to [../re/ram-limit.md](../re/ram-limit.md).

A string pool: + 0x04 flags (bit 0 = share: search for an equal string before the add and keep reference counts), + 0x08 index handle (8 bytes for each entry: offset and length), + 0x0c reference count handle, + 0x10 text handle, + 0x14 count. The other pool functions are 0xa71d8 (lock), 0xb9ef4 (unlock), 0xe1cc8, 0x95a80, 0x95ad0, 0x10a650, 0x10ed14 and 0xb3e0c. 0x9eff8 has 6 calls in 4 functions (0x9f0c4, 0xb5828, 0x9c288, 0x21c1e0). Static. 0x105cb8 makes the pools of the database with 0x947f8 (pool, flags): flag 1 for artist, artist sort, album, grouping, genre, file type, EQ and type 19. 0x947f8 clears bit 0 if 0x9d9d0 (SysInfo + 0xe0, the RAM size) is more than 0x3ffffff. Thus a 32 MB iPod shares equal strings and a 64 MB iPod does not. 0x95ad0 (pool, index) removes an entry (with bit 0: only when the reference count becomes 0). 0xb3e0c replaces an entry. 0xffaf4 removes all strings of one track. Static. With 5,000 test tracks, the pools used 1,047,936 bytes (about 210 bytes for each track). Emulator.

### Shuffle

Refer to [re/shuffle.md](../re/shuffle.md). The reference model [re/shuffle-model.py](../re/shuffle-model.py) gives the same order as the firmware in the emulator.

| Address | Function | Evidence |
|---|---|---|
| 0x09edb0 | (app) → the Shuffle mode: 0 if `+0x20` is 0, else 2 if `+0x92`, else 1. The Settings controller (0x1929a0, 0x193b9c) and the accessory commands (0x1f4a48, 0x1f4b70, …) call it. | Static |
| 0x0a983c | (settings): sets the byte "changed" `+0xb74` = 1. The settings are then saved at the next sleep. | Static |
| 0x11147c | (app): the refresh after a change of Shuffle. The setter 0xb3a04 ends with a tail call to it. | Static |
| 0x0b3a04 | Shuffle setter (app, mode): 0 = Off, 1 = Songs, 2 = Albums. Sets the settings bytes +0x20 (on) and +0x92 (albums). | Static |
| 0x0b40c4 | Starts a shuffled play list. Calls 0x94440 with settings +0x92 and +0x93. Writes the new position to the track item +0x24. | Static, Emulator |
| 0x094440 | The music shuffle (list, current track, albums, shuffle in albums). Fisher–Yates from the end. Songs: slot 1, then the current track goes first. Albums: slot 6, groups of the same album name, then the group of the current track is swapped with group 0. | Static, Emulator |
| 0x0d1df0 | (track list): makes a play list item. Item + 0x10 is the result of the counter 0xa01e8, not a track ID. Item + 0x20 is the track object. The dbid is at track + 0x108. Track + 0x20 was 0 at run time on the real iPod, although 0xd7888 writes mhit + 0x10 there. | Static, Patch |
| 0x09e96c | (app): the Repeat value for the menu: settings `+0x1c`, with 1 and 2 swapped. The Settings controller keeps it at `+0x1d`. The patch `playback-log` uses it. | Static, Patch |
| 0x0e5978 | Random index 0 … n − 1. Seeds itself one time after a start. Then it cuts n to 16 bits (`asr #16` at 0xe59bc) and jumps to 0xaf4b4 with the state at 0x1081e048. The patch `shuffle-fixes` removes the cut and hooks the seed call at 0xe59a0. Its only callers are in 0x94440 (0x9460c, 0x946d8, 0x94758). | Static, Emulator |
| 0x00055c | Seed: `A XOR (B << 16)`, A and B are two reads of 0x60006038. | Static, Emulator |
| 0x0a501c | `b 0x55c`. 0xe5978 calls the seed through this jump (`bl` at 0xe59a0). | Static |
| 0x1120bc | Gets the cached track list of a slot (1 = database order, 6 = album order). | Static, Emulator |
| 0x0ddf94 | Sorts a track list for a slot. | Static |
| 0x0bb28c | Smart playlist evaluation. Selection type 2 (random) calls 0x94440. | Static |
| 0x0a2310 | Makes the object `app`. Stores its first argument (the playback settings) at `app + 0xca0`. Called from 0x1ebe9c. | Static, Emulator (settings 0x13e34c74) |
| 0x15d9bc | Constructor of a global object (method table 0x669b18). Writes `+0x90` … `+0x96` of a part at `+0x6c` from its arguments. It is not the playback settings. | Static, Emulator |
| 0x25de24 | C++ static constructor. Calls 0x15bbb8, 0x15f8a0 and 0x15d9bc with `(2, 2, 1, 0)` at base 0x149dd438 + 0x90, + 0x11c and + 0x200. | Static |
| 0x0af4b4 | (state pointer, n) → index. Park–Miller (16807, 2³¹ − 1, Schrage form), then `int16(float32(n) × float32(state) × 2⁻³¹)`. Keeps n in r7. The 16-bit cut of the result is at 0xaf514–0xaf518. Users: 0xe5978 (music) and the card game deck shuffle 0x12d494. | Static |
| 0x143660 | Photo slideshow shuffle. Only the window of loaded photos, with `rand() % n`. | Static |
| 0x11ac38 | C `rand()`: `1103515245 × state + 12345`, `(state >> 16) & 0x7fff`. Not used for music. | Static |
| 0x11bb18 | C `srand()`. | Static |

### The play list and On-The-Go

Refer to [re/play-next.md](../re/play-next.md).

| Address | Function | Evidence |
|---|---|---|
| 0x196418 | Returns the play list object: the songs that play now (pointer at 0x1081d9cc, vtable 0x66cad4). The constructor is 0x196de0. | Static, Emulator |
| 0x1960b0 | (play list, browser, list, start row, …): fills the play list from a list and sets the current index (+0x14). | Static |
| 0x0abb98 | (browser, row, …): starts a list at a row. Calls 0x1960b0, then 0xacd80 or 0xac6f4 on the player. | Static |
| 0x2358fc | (list object, browser, row, source list, sort, flag): adds one row (0x92bbc) or, with row −1, all rows (0x9388c) at the end of the track list at object + 4. | Static |
| 0x0adbb8 | (browser, row): Add to On-The-Go (library + 0xce0). Row −1 adds all rows. Limit 1000 songs. If the play list is On-The-Go (+0x18), it also calls the play list + 0x10. | Static |
| 0x1eb5a4 | The script function for Add to On-The-Go. Calls 0xadbb8. | Static |
| 0x0bbf2c | Writes `iPod_Control\iTunes\OTGPlaylistInfo`. | Static |
| 0x1eb5a4 | (JS browser, row, browser): `mov r4, r0`, `movs r0, r2`, `ldreq r0, [r4, #0x1c]`, then `bl 0xadbb8` at 0x1eb5b4 with r0 = browser and r1 = row. The script calls it at a hold of Select (lr 0x120bf0 in the interpreter). The `up-next` patch hooks 0x1eb5b4. | Static, Emulator, Patch |
| 0x235a54 | (list object, i): the item at play position i: slot 1 with the shuffle bit (track list + 0xec bit 0) off, else slot 2. | Static, Patch |
| 0x093504 | (item, track list, cursor, 0): a new item for the same song, linked with 0xd6614. | Static |
| 0x0d6614 | (item, cursor {parent, after}, notify): links an item after `after` (−1: at the end, 0: at the start). Adds 1 to the count (parent + 0x32). With notify, calls 0x1137c4. | Static |
| 0x1137c4 | (track list): frees the sorted arrays and index maps of all slots. | Static, Patch |
| 0x0b0d0c | (track list, field): frees the caches of the slot of one field (+ 0x174, + 0x238, + 0x2fc, + 0x3c0, + 0x494). The shuffle uses the field 0x1000 (slot 2). | Static |
| 0x09e57c | (item, 0x33, 0): the play position of an item. | Static, Patch |
| 0x1968c0 | (play list, song, flags): the next item in the play order. Flag 4 writes its index to + 0x14. The "next song" action 0xac4c4 calls it at the change of song. | Static |
| 0x0ac4c4 | (player, flags): the "next song" action. The current item is player + 0x2a4. It calls 0x1968c0 (at 0xac55c), then 0xac6f4 or 0xeb610 for each item until one plays. With no next item, it calls 0xeb610 (player, 0, 0) at 0xac588 and the player stops. Refer to [../re/playback-log.md](../re/playback-log.md). | Static, Patch |
| 0x0ac6f4 | (player, item, flags): plays an item. Calls 0xeb610 (at 0xac750), 0x10b894 (at 0xac7b4) and 0xd9b70. Returns 0 if the song plays. | Static, Patch |
| 0x0eb610 | (player, item, flags): sets the current song. Item 0: no song. −0x32: the song cannot play. −0x6c: no memory (0xa8dc4 gives 0). | Static, Patch |
| 0x10b894 | (player, item, flags, out, cache): probably the open of the decoder. Returns an error code. | Static, Patch |
| 0x2aa350 | Data: the sort description of slot 2 (first key: field 0x1000, the shuffle position at item + 0x24). | Static |

### The EQ

Refer to [re/custom-eq.md](../re/custom-eq.md). The EQ is a software EQ. A preset is a chain of up to 5 filter numbers (0 = no filter). Each number selects a record of 2 Q24 biquads, for 44100 Hz and 48000 Hz. The table has 55 records.

| Address | Function | Evidence |
|---|---|---|
| 0x0a6bd0 | Makes the 22 Apple presets: the names from 0x2a9cc0, 10 float values each from 0x2a9d18 (× 100, as i16). The values are filter numbers, for example Bass Booster = 4. | Static |
| 0x0e07f4 | (library, name): finds a preset in the list at library + 0xbec. | Static |
| 0x09bf6c | (library, name, out): copies the preamp (+0x21c) and the 10 values (+0x21e) of a preset. | Static |
| 0x0ace48 | (player, values, per track): copies the values to player + 0x214 and calls 0x10191c. | Static, Emulator |
| 0x10191c | (player, 0, values): with the EQ on (player + 0x235), calls 0xf4dc0 and 0xe6838; with the EQ off, 0xec450. | Static, Emulator |
| 0x1446e8 | Sends command 0x1f with the first 5 values (each 0 … 0x60) to the audio engine (message queue 2). The selection of Bass Booster in the emulator wrote nothing to the codec. | Static, Emulator |
| 0x14493c | Sends command 0x1a: the EQ on or off. | Static, Emulator |
| 0x0a6d34 | Clears the preset list and calls 0xa6bd0 at 0xa6d68. `custom-eq` hooks this call. | Static, Patch |
| 0x0d83d0 | (library, buffer of 0x218 bytes): adds a preset, sorted by name. Name at +2, 10 values at +0x204. | Static, Patch |
| 0x24addc | The switch on the command at state + 0x12f8. Case 0x1f calls 0x23f274, case 0x1a calls 0x23fe24. | Static |
| 0x23f274 | Copies the 5 filter numbers to object + 0x650, then runs 0x23fe3c. | Static |
| 0x23fe24 | Sets or clears bit 1 of object + 0xcc: the EQ on or off. | Static |
| 0x23fe3c | Writes the coefficients of the 5 stages to the IRAM block 0x40000fe4. It negates a1 and a2. | Static |
| 0x0f90fc | Returns the count of filters (RAM 0x10823754, 55). | Static, Emulator |
| 0x0dbd84 | (number): returns the address of a filter record. The table pointer is RAM 0x10823758. | Static, Emulator |
| 0x0cfe9c | Sets the table pointer: 0x1082375c, or + 0x898 for codec type 2. | Static, Emulator |
| 0x6a1a00 | Data: the filter table of codec type 3. 55 records of 40 bytes. The start code copies it to RAM 0x1082375c. | Static, Emulator |
| 0x2403c4 | Calls the EQ for each block of 0x100 frames. The decoder step 0x24ab48 calls it. | Static |
| 0x71706c | The EQ (IRAM 0x40000ed0). Only 16-bit audio at 44100 Hz or 48000 Hz. | Static |
| 0x7163b0 | One biquad stage, Direct Form I, Q24, for 2 channels. | Static |
| 0x7164c8, 0x7164e8 | Copy the samples with `<< 9`, and back with `>> 9` and a limit to int16. | Static |
| 0x265e54 | (mode): sets the state of the codec (mode 1, 2 or 3). Calls the routine of the codec type: 0x28386c (type 1), 0x283c30 (type 2) or 0x2839b8 (type 3, WM8758: R52–R55, R49, R1–R3). It runs at the start, at playback and after a wake. | Static, Emulator |
| 0x2653a4 | Returns the codec type (1, 2 or 3). The emulator uses type 3. | Static, Emulator |
| 0x2840d8 | (bytes): writes one codec register: I²C address 0x1a, 2 bytes ((register << 1) \| bit 8, bits 0–7). Takes the codec mutex. | Static, Emulator |
| 0x282f58 | (7-bit address, count, bytes): the low I²C write (I²C controller 0x7000c000). | Static, Emulator |

The codec functions above come from the hardware EQ test (refer to [re/custom-eq.md](../re/custom-eq.md#the-hardware-eq-of-the-codec)). The test patch is on the branch `hw-eq`.
| 0x20fcf8 | The task of message queue 2. Commands 0x1a and 0x1f go through the ring queue 0x2354cc to 0x249ab8, which writes the command to state + 0x12f8 and the data to state + 0x12fc. 0x24addc reads them. | Static |

### The browser and the menus

Refer to [re/album-artist.md](../re/album-artist.md#album-artists-menu-item-15-october-2026). The `album-artists` patch uses these functions.

| Address | Function | Evidence |
|---|---|---|
| 0x0d080c | (browser, x, field, sub): builds the list of a field. Field 4 = Artist (sort list 7, browser + 0xc48/0xc4c/0xc50), 2 = Album (6), 0x40 = Genre (9), 0x4000000 = Composer (0x18). Does nothing if the list is there. | Static, Emulator, Patch |
| 0x09dec4 | (browser): builds the Artists list and returns the count. | Static, Emulator |
| 0x09cb10 | (browser, row, out): the letter of a row for the fast scroll. Uses the letter table of the main browser (+0xc4c). | Static |
| 0x0b2620 | (browser, row): selects a row. +0x10 = row; the name goes to +0x228. | Static |
| 0x0a34b8 | (browser): clears the Artists list (frees +0xc48 and +0xc4c with 0xa7f9c). | Static, Patch |
| 0x09bb98 | (browser): the track database of the browser (the sort lists). | Static, Patch |
| 0x09c8e4 | (db, list, 0, n): entry n of sort list `list`. | Static, Patch |
| 0x09e418 | (entry): the track of an entry. | Static, Patch |
| 0x1142a8 | (browser, entry, 0): the filter. Bit 0 of the result is 1 if the track agrees with the selections (genre +0x28, artist +0x228, composer +0x428, album +0x628). Calls 0x9f904 for the Artist at 0x114354. | Static, Patch |
| 0x09f904 | (track, &text, &units): the Artist text of a track. | Static, Patch |
| 0x09efe0 | (pool, index, &text, &bytes): a view of a pool string. | Static, Patch |
| 0x091c7c | (data, a, a units, b, b units): the text compare of the lists. | Static, Patch |
| 0x091d44 | Compares two tracks by one field (the field bit in argument 5). | Static |
| 0x0a7200, 0x0b9f20 | (track data): lock and unlock of the string pools. | Static, Patch |
| 0x0a8178, 0x0a7f9c | Allocate and free. The browser lists use this pair. | Static, Patch |
| 0x0a96c0 | Makes a track object from the slab at db + 0x38. | Static |
| 0x088bc0 | Makes the extension object of a track (track + 0x10) when it is necessary. | Static |
| 0x23ca4c | `activate(list, row)` of a menu list: calls 0x239f7c(list, row, tag), which sends the selection event. | Static, Emulator, Patch |
| 0x239f7c | (list, row, tag): sets the selected row (vtable +0x15c). With tag 0 it returns before the selection event (vtable +0x194); `usb-audio-out` uses this to draw its main menu row again. | Static, Emulator, Patch |
| 0xd3390 | The loop of Apple's USB host task (made at 0x119388 by the host start, priority 0x10): the message receive 0x2782f4 with 1 tick at 0xd33b0, then the poll 0xb9004 if no message came. About 1000 polls each second in host mode. `usb-audio-out` 1.4 hooks the receive. | Static, Emulator, Patch |
| 0x2782f4 | (queue, buffer, size, ticks): receives a message. ticks 0: a wait with no limit (0xd1e78); else a wait of at most `ticks` (0xeb034 → 0xa0e44 → 0xa697c). Returns the size, or -1. | Static |
| 0xb9004 | The poll of the USB host stack: method +0x64 of 16 slots (0xc7544), 0xf176c, 0xdda08, method +0x70 of 16 slots (0xeccec). | Static, Emulator |
| 0x97230 | The UIM stop: USBCMD = 0, then a wait with no limit for HCHalted (USBSTS bit 12). In the emulator this wait does not end. | Static, Emulator |
| 0x2183ec | (menu data, row): the item object of a visible row. Skips the hidden items. | Static, Patch |
| 0x21845c | (menu data): the count of visible items. | Static |
| 0x19e644 | (menu screen): the script calls it to activate the selected row. | Emulator |
| 0x1e7b98 | (JS browser): resets the native browser (+0x1c) at the start of a browse. | Static, Emulator |
| 0x1e7628 | (JS browser, mode): calls 0xb4038(browser, mode). Artists uses mode 1. | Static, Emulator |
| 0x1e7b98 | (detail) The Artists item of the Music menu runs it one time, the Artists item of the main menu two times. Composers, Genres and Playlists do not run it when they open. | Emulator, Patch |
| 0x105a04 | (label): the bit of a main-menu item in the main menu mask (a `switch` on the labels 0x5f7c–0x5f9f). Unused bits: 0x4000, 0x20000000, 0x40000000, 0x80000000. `shuffle-album-mix` uses 0x20000000, `album-artists` uses 0x40000000 and `usb-audio-out` uses 0x80000000 (a `b` hook with `chain` on the first instruction, `sub r0, r0, #0x5c00`). Only 0x4000 stays free, and it is inside the merge mask 0x1fffffff. | Static, Patch |
| 0x193470 | (settings, label): 1 if the main-menu item is on (mask AND bit). | Static, Patch |
| 0x19351c | (settings, label, on): writes the bit into the mask and sets the byte "changed" (+0xb74). It does not write the settings file. The `instant-save` patch hooks its first instruction. | Static, Emulator, Patch |
| 0x09d880 | (settings): the main menu mask, (main browser + 0xca0) + 0xb34. Emulator default: 0x0e180201. | Static, Emulator |
| 0x0af838 | At the load of old preference versions: merges new default bits into the mask, with the mask 0x1fffffff. | Static |
| 0x19ed58 | (screen, menu, label, 3, visible): shows or hides an item of a menu (item byte +4, bit 0 = hidden). The UI script calls it for each Apple item of the main menu (Menu 24094) at the start and each time the main menu shows. | Static, Emulator, Patch |
| 0x24bc38 | (label, menu, visible): calls 0x19ed58 on the menu screen. Search (0x130b70) and Contacts (0x1b9ed0) use it at the start. | Static, Emulator |
| 0x130b30 | Returns 0 on a 5G and 1 on other models: 0 if `HwVr` (0x265164) has the generation 0xb and a board revision below 0x11. It does not read the RAM size. Only Search uses it (0x105a04 label 0x5f8b, 0x130ca4). The patch `search-5g` changes 0x130b50 (`movcc r0, #0` to `#1`). Refer to [re/search-5g.md](../re/search-5g.md). | Static, Patch |
| 0x130ca4 | Builds the Music menu (0x7600). If 0x130b30 returns 1, it adds the two Search items. It makes the task `SearchHelperThread` (0x155e7c). | Static |
| 0x253fe4 | (item): 1 if the item is visible (item byte +4, bit 0 = 0). | Static |

### The Playlists screen

Refer to [../re/playlist-folders.md](../re/playlist-folders.md). The `playlist-folders` patch uses these functions. Screen row r shows entry r + 1 of the playlist array. Entry 0 is the master playlist.

| Address | Function | Evidence |
|---|---|---|
| 0xb4a64 | The database load. Makes the playlist array: main browser + 0xcfc (pointers), count at + 0xd00. It leaves out New Voice Memos, the podcast playlists (library + 0xce4) and some empty playlists. | Static |
| 0x9e008 | (browser): the count of the playlist array. | Static, Emulator, Patch |
| 0x9cf90 | (browser, index, out): the name of entry `index`. `out[0]` is the count of UTF-16 units, then the text (0x9e42c). | Static, Emulator, Patch |
| 0x9cf58 | (browser, index): the low word of the persistent ID (playlist + 0x18) of entry `index`. iAP only. | Static |
| 0x9cfe0 | (browser, index): the count of songs of entry `index` (root + 0x32). iAP only. | Static |
| 0xa39c4 | (browser, index): 1 if entry `index` is On-The-Go (library + 0xce0). | Static, Patch |
| 0x9e99c | (browser, index): playlist + 0x16c of entry `index`. 0x1eb9fc and 0x1edf54 read all entries. | Static |
| 0x914ac, 0xb29b0 | (browser, index): selects entry `index`: browser + 4 = the playlist. Returns 0, or −50 for an index that is not in the array. | Static, Emulator, Patch |
| 0xb2d1c | (browser, index): writes the persistent ID of entry `index` into the settings (+0xb2c, +0xb30). | Static |
| 0x1ea660 | (JS browser): the count of the screen (`bl` 0x9e008 at 0x1ea66c). Stores count − 1 at JS browser + 0xd4. If it changed, it calls `vtable+0x54(js, 'VMax', 0x6387)`. | Static, Emulator, Patch |
| 0x1ec614 | (JS browser, …, element, row, out): the data of a row. Element 0x6425 calls 0x9cf90(browser, row + 1) at 0x1ec914. | Static, Emulator, Patch |
| 0x1e7e34 | (JS browser, row): selects a row. Writes JS browser + 0x3ec = row and calls 0xb29b0(browser, row + 1) at 0x1e7e7c. The script opens the songs of the row also if it returns 0. | Static, Emulator, Patch |
| 0x254cac | (JS browser, row): 1 if the row is On-The-Go. Calls 0xa39c4(browser, row + 1) at 0x254cc4. | Static, Patch |
| 0x4fcd58–0x4fcf00 | The table of C++ member pointers (address, 0) of the JS browser methods that the script calls, for example 0x1e7e34 at 0x4fcd60. | Static |

`vtable+0x54(js, 'Str ', 0x6387)` makes the list read its labels again. The functions near 0x165000–0x16f000 that read the array are the iPod Accessory Protocol.

### The video processor

Refer to [re/video-player.md](../re/video-player.md). The ARM code sends text commands to the BCM2722 (VideoCore). The test patch `video-log` (only on the branch `video-log`) hooks 0xe9358 and 0x2872c0. "Patch" in the evidence column means that patch, on a real iPod.

| Address | Function | Evidence |
|---|---|---|
| 0x287664 | Sends a command and reads the reply (reply, size, format, ...). Variadic. Result: 0, or -1 if the channel is not open. | Patch |
| 0xe9358 | Formats and sends one command (format, pointer to the arguments). Takes the lock 0x123000. Result: 0, or -1 if the channel is not open. | Patch |
| 0x2872c0 | Reads the reply (buffer, size). Releases the lock through 0x287140. Result: 0 if the reply has more than one byte. | Patch |
| 0x287110 | Sends a command and reads the reply, with no check of the send. Used for `load_application` and `end_application`. | Static |
| 0x2874f0 | Sends a command with no reply. | Static |
| 0x7b114 | `vsnprintf` (buffer, size, format, pointer to the arguments). | Patch |
| 0x7b240 | `snprintf` (buffer, size, format, ...). | Patch |
| 0x1f9404 | Sends `mp_get_status` and decodes `state`, `substate`, `paused`, `duration` and `elapsed`. | Static |
| 0x1f9754 | Sends `mp_get_stats video` or `mp_get_stats audio` (0x400-byte reply) and reads the counts of lost frames. | Static |
| 0x1fa394 | Sends `mp_selectplay passthru:%s %d` (player vtable slot +0x34 of the table at 0x671dc0). | Static |
| 0x1f8e84 | Sends `mp_play` (slot +0x40). | Static |

### USB audio

Refer to [re/usb-audio.md](../re/usb-audio.md). No patch uses these functions yet.

| Address | Function |
|---|---|
| 0x24d628 | Makes the composite USB device "iPod USB Interface". |
| 0x170f2c | The USB task. |
| 0xd85d8 | Sets the device descriptor values (vendor 0x05AC, product 0x1209 for the 5.5G). |
| 0x132614 | Makes the audio streaming object (vtable 0x666958). |
| 0x1e3064 | (source, bytes): takes a 192-byte packet buffer from the pool (0xd3e70, 24 buffers in IRAM at 0x4001e580) and fills bytes / 4 stereo frames from the queue of the source (0x1e2c90), with the rate converter (0x1e2de0). An empty queue gives silence. Source + 1 not 0: a test signal (0xdbdb4). |
| 0x1e2bdc | Gives a packet buffer back to the pool. |
| 0x1e2f74 | (source): 1 if the music may go to USB. Source + 8 = 0: 0 while the byte at RAM 0x1081dff6 is 0 (an iAP "Digital Audio" accessory sets it); then the byte at 0x1081e018 = 1: the rates must be equal or ×2 or ×4 (0x1e2f38). 0x1e3064 gives silence (0x1e2c90 with r3 = 1) if it returns 0. Static, Emulator. |
| 0x205cfc, 0x205db4 | 0x205cfc makes ArtworkLoadTask (0x11c808, stack 0x8000); 0x205db4 is its loop: the wait on task + 0x4c (0xd1e78), the gate 0x94bbc(0x19) (if 0: 0x94e6c(0x19, 0) and a sleep of 1.5 s), the lock task + 0x40 (0xd6a64), the request lookup 0x2065c4, the artwork lookup 0x1f161c (0: no art), 0x29e024, the image load 0x2258a4 and 0x225594, the release 0x94d80(0x19, 500). Static, Emulator. |
| 0x2055dc, 0x205854 | In ArtworkLoadTask: the only call of the artwork lookup 0x1f161c, and a call of the image load 0x2258a4. 0x2258a4 has 15 calls. The patch `diagnostic-log` hooks these two calls. | Static, Patch |
| 0x94bbc, 0x94e6c, 0x94d80 | The client requests to the kernel port 0x14 (0xa6770, the lock 0x12b): query (type 1), request (type 0), release after a delay in ms (type 2). The client is the first argument (0x19 artwork, 0x27 audio playback, 0x24 the USB audio area, 3 …). Static. |
| 0x284b0c | The server task of the port 0x14 (receive 0xa66a4): 45 clients, a byte "active" and a release timer for each. A query is granted if the state of 0x2651e4 is set or a client is active. Static. |
| 0x2651e4 | Reads the register 0x52 (or 0x86) of the power chip (0x282ad4) and gives a state bit to the port 0x14 server. Static. |
| 0x1a3080 | Makes the audio output object and sets +0x58, +0x59 and +0x5a (the USB route) to 0. Called at 0x18c770 and 0x1b8054. Static. |
| 0xded04 | The idle routine of the kernel: sleeps the core (CPU_CTL 0x60007000 = 0x80000000) and adds the idle microseconds (timer 0x60005010) to the statistics at RAM 0x14983040 (+0 and +8 for the two cores, 64 bits; +0x10 and +0x18 the counts). Static, Emulator. |
| 0x82694 | Unsigned division (r0 / r1): the quotient in r0, the remainder in r1 (`__aeabi_uidiv`). Static. |
| 0x20620c | (art cache): fills the request queue of ArtworkLoadTask. Gates: the play queue exists (0x196418, method +8), the count of 0x2059d0 is not 0, + 0x78 is not 0, and a budget from the capacity + 0x74 (cap × 0.95 − size of format 8). Static. |
| 0x206b78, 0x206b98 | Methods + 0x10 and + 0x14 of the art cache (vtable 0x6732a4). 0x206b78: + 0x70 = + 0x71 = 1, the capacity + 0x74 = 0x100000. 0x206b98: + 0x70 = 0, + 0x74 = 0, clears the queue + 0x50, + 0x72 = 1. Static. |
| 0x1bfef0, 0x1bfb74 | The library singleton (RAM 0x10882b70), and the art cache with an identifier (0x1bfb74(library, 0) is the cache of ArtworkLoadTask). Static. |
| 0x1bfb94, 0x1bfd18 | The library open (calls 0x206b78 for each cache, reserves memory with 0x1f15b0) and close (library + 0x54 = 0, + 0x55 = flag, calls 0x206b98 for each cache, 0x1f16c4). Callers of the close: 0x1ed828, 0xb4fe4, 0x16e85c, 0xb2dc8, 0x201b4c. Static. |
| 0x1ee8d0 | (app, on): with on not 0, the library close (0x1ed828) and then the open (0x1ed918); with on = 0, no close. Called by the UI state machine 0x1d8cd0 when 0x197e70 returns 1. Static. |
| 0x1bfe84, 0x1c020c, 0x1c00e8, 0x1bfe18 | The track art request. 0x1bfe84(library, track id): puts the track into the library queue (+0x10) and posts the event 0x55000000 (0x1300f4, 0x13d6d4). The library handler 0x1c020c (event type 0x10, codes 2, 0x52800007, 0x55000000, 0x55000001) calls 0x1c00e8 if the library is open; 0x1c00e8 gives each track to 0x1bfe18, which calls the method + 0x1c of each cache entry with the byte + 8 set. Callers of 0x1bfe84: 0x87cec (a new track in the player), 0x248964. Static. |
| 0x206c5c, 0x2054ac, 0x206860, 0x205e64 | Art cache methods + 0x1c and + 0x20: put {track id, 1 or 0} into the cache queue (+ 0x20). The task (0x206860) empties the queue: 0x205e64 adds the track with its art formats (+ 0x78 increases by 1 for each format); 0x20661c removes it. 0x2052f0 and 0x1eb2b0 (Now Playing, formats 7 and 8) only read the list. Static. |
| 0xa1ff0, 0x91164, 0xb4fe4 | The ArtworkDB handle at database + 0xd2c (the database is the app + 0x1c; the app pointer is at RAM 0x1081da18). 0xa1ff0 (from the first load 0xb4a64) opens `iPod_Control\Artwork` (0xa9190) and loads `ArtworkDB` (0xafd5c), then copies the handle to + 0xd14. 0x91164 frees the handle and writes 0. The database reload 0xb4fe4 calls 0x91164 and the library close 0x1bfd18(library, 0); it does not call 0xa1ff0. 0x9b0a0 (the art lookup of a track) returns nothing when + 0xd2c is 0. Static. |
| 0x1e9f9c, 0x1e78e8, 0x1ed9f0 | The database reload after a disk change. The app event 0x63800003 (0x1eccdc) calls 0x1ed9f0: if the app + 0x489 is set, it sets the reload flag + 0x484. 0x1e9f9c (from 0x1eeb54) calls 0x1e78e8 → 0x1ec2c8 → 0xb4fe4 when + 0x484 is set, no modal screen is active (+ 0x66), the photo import state is not 0xb, and the USB device state (0x24d88c, RAM 0x108711d4 + 0x218, read by 0x24d8e4) is 1. 0x1e78e8 sets + 0x48a. The notification handler 0x1e0458 (case 8, 0x18ae70) sends 0x63800003. Static. Real iPod (probe 1.16): this reload does not occur in host mode. |
| 0x9a0f8 | (ArtworkDB, unused, dbid low, dbid high, indexed): finds the ArtworkDB entry of a track. The object must start with 0x6974696c (0xa137c). With indexed = 1 and + 6 = 0, it uses the sorted index + 0x620 (made at the first use by 0xa92ec and sorted by 0xadc20, under the lock + 0x614); else it searches the list + 0xc (entry + 0x10 and + 0x14 = dbid). Static. |
| 0x1e9e88, 0x1e8d10, 0x1e9c84 | The volume methods of the app (UI task). 0x1e9e88(app, level) sets the level (0–100) at app + 0x758; 0x1e8d10(app, step, show) is volume up and 0x1e9c84 volume down; show = 1 opens the overlay (0x1eaacc). All call 0x88ff8, 0xb4078 and then 0x1eee50. Static. |
| 0x1eee50 | (app, output volume 0–256): writes app + 0x40c and sets the status icons. If the byte at app + 0x434 is not 0, it uses the value at app + 0x430 and sends the volume with the property 0x607c (0x1928f4). The normal path sends the volume through 0xb4078. Static. |
| 0x1d8aa4 | The key handler of the UI (from 0x1d81cc, for key types 4–7). Key codes (the Simple Remote codes 0x38–0x4c): 0x3a stop, 0x3b play, 0x3c pause, 0x3d mute, 0x3e and 0x3f next and previous chapter, 0x47 and 0x48 fast forward and rewind (0x1ec3c0, 0x1eefe8). Static. |
| 0x2141fc, 0x222d74, 0x13d524 | A key event: 0x2141fc(0x14) allocates 20 bytes, 0x222d74 fills the type, the source and the code, and 0x13d524 calls the handlers at once in the current task. The key class methods: 0x13d148 (type 4), 0x13d4b8 (5), 0x13d4f8 (6), 0x13ce10 (7). Static. |
| 0x13d6d4 | (event, target, async, sender, 0): with async = 1, puts the event into the message queue of the task of the target (port: target + 0xc → + 0xc → + 0x1c; 0x151c10 → 0x1517d4). With sender = 0 it reads the context of the current task (0x101800 + 0x1c). The app target is at RAM 0x1081da80 (0x1d2ee8, 0x1d32e0). A key event posted in this way does not reach the key handler 0x1d81cc (real iPod, probe 1.22). Static, Real iPod. |
| 0xd9cec | (type, error): the USB host message to the UI (notification 0x12 through 0xcd314), for example "unsupported device". Callers: 0xd399c (add device 0xd377c), 0x10c204, 0xe2be0, 0xc0c38 (`bleq`). Errors of 0xd377c: 0x673 and 0x67d (hub not allowed), 0x68c (no driver). Static. |
| 0x9ba00 | (database): the play state: 1 playing, 2 paused, else stopped. 0x1e798c (= 1) and 0x1e7848 (= 2) use it. Static. |
| 0x13221c | Apple's USB stream stop: the stream off (state + 2), the cancel of endpoint 0x81 (0x24bf7c), the route to the codec (0x1a2fa0) and the flush of the USB buffers (0x1a2fa8). Static. |
| 0xb95a4, 0x184aec | The USB mode task and its manager (pointer at RAM 0x1081edc4): the clients idle (0, 0x24d7a4), device (1, 0x170fec) and host (2, 0x1422e8). The task starts mode 1 at USB power and stops mode 2 at 0xb9614 (`bleq 0x18482c`). Static. |
| 0x184860, 0x18482c | Manager: start mode m (only from mode 0; the stop of client 0, then +0x14 and +0x18 of client m) and stop mode m (+0x24 and +0x28 of client m, then the start of client 0). The mode is byte +0. Static. |
| 0x1422c0, 0x142298 | The host client: start (Camera Connector "on", host start 0x2860e8, state 3) and stop (host stop 0x28608c, Camera Connector "off", state 5). Static. |
| 0x28608c | Apple's host stop: 0xb9358(1), a sleep of 2 s, 0xb963c, the UIM finalize (dispatch table + 8), frees the pools at + 8 and + 0xc. Static. |
| 0x170f24, 0x170ec0 | The device client start: 0x170ec0(obj, 3) writes the state + 6 and wakes USBDeviceTask (event + 0x10). Static. |
| 0x11c808 | Makes a task: (name, entry, argument string, priority, stack size, a, b). Static. |
| 0x170f2c | The USB device task: waits until its state (+6) is 3 (USB power), then the device start 0x24d3c4 (at 0x170fc8), the session 0x24cd34 (at 0x170fd8) and the stop 0x24d49c (at 0x170fe0). Static. |
| 0x24d3c4, 0x24cfac, 0x220e0c | The device mode start: 0x220e0c sets up the endpoints, sets a USBCMD bit (0x2204f8) and installs and enables the device interrupt handler 0xcd8e0 (0x18a870, 0x18a824). 0x24d3c4 returns not 0 if the start failed. Static. |
| 0x24cd34 | The device session: runs while OTGSC bit 11 (VBUS) is set (0x220278); tests and clears USBSTS bits (0x220b80); ends when the abort flag RAM 0x108318ec + 5 is set. Static. |
| 0x24d49c, 0x220f34 | The device stop: removes the device interrupt object (0x18a888), stops the controller and resets it (USBCMD), with a wait without a limit. Static. |
| 0x970a8, 0xe8c20, 0xe0074 | UIM delete endpoint (dispatch table 0x6c8820 + 0x50). The async unlink 0xe8c20 waits without a limit for USBSTS bit 15 = 0 (empty list) or bit 5 (async advance, after the doorbell). The periodic unlink 0xe0074 stops after 150 tries. Static. |
| 0x2856a4, 0x1710d0 | `USBPowerSense`: watches the VBUS GPIO (0x2218ac); 0x1710d0 sends the notifications 4 and 5 (0xcd30c). Notification 4 gives the app events 0x6380000d and 0x6380000e (0x1ebb6c: app + 0x485; a pause of the music when the power goes away). Static. |
| 0x1ac198 | (code, down, interrupt): a key push or release to the UI task: a `kDwn` or `kUp ` message (0x151a40). The codes are 0–0x78. Callers: the front buttons (0xada4c), the Simple Remote (0x1e6a84). Static, Real iPod (probe 1.23 uses it for the EarPods buttons). |
| 0x1e6a84 | The Simple Remote handler: each bit of the button mask to a key code (table 0x63ef30: play/pause 0x1c, volume up 0x20, volume down 0x1f, next 0x1e, previous 0x1d, stop 0x3a, …), then 0x1ac198. Static, Real iPod (probe 1.23 uses the codes). |
| 0x2564b0 | Returns the key code of an event: bits 16–23 of event + 0x10. Static. |
| 0x19a51c, 0x197e70 | The photo import service (0x1d3050(0x4280), then the type check 0x222dd0); 0x197e70 returns 1 if its state byte + 0x1c is 1–5 or 7. The object is made at the start (0x69ce28 → 0x19a48c → 0x19b198, state 1) and kept at RAM 0x1081e97c; 0x19b014 sets the state. Static. |
| 0x1d56e0 | Sets the byte at RAM 0x1081dff6 if a special file exists in `iPod_Control\Device`. 0x1e2f74 reads this byte. Static. |
| 0xfed68 | (buffer, flag): gives a decoder buffer back; calls vtable + 0x18 of the audio output object (0x1a2924 with −1): the decoder gives its next buffer (0x1a2d60). |
| 0x1e2c90 | The queue of the USB source (source + 0x10): 6 entries of 12 bytes (buffer, release handle, frames), write index +0x5c, read index +0x5e. An empty entry gives its buffer back to the decoder (0xfed68). |
| 0x1a2d60 | The audio output gives a decoder buffer: to the USB source (0x1e2bc8) if output + 0x5a is 1, else to the codec driver (vtable +0x18). |
| 0x1a2fa0 | (output, on): output + 0x58 = on; +0x5a and the byte at RAM 0x108236a6 = +0x58 and +0x59. |
| 0x1a3070 | Returns the audio output object (RAM 0x108236a8). |
| 0x1e30d0 | Returns the USB source object (RAM 0x10831964). Source + 4 the rate of the music, + 0xc the output rate (default 44100). |
| 0x1e2f60 | (source, rate): sets the output rate of the converter. |
| 0x132038 | The USB audio stream loop: 12 packets from 0x1e3064, send (0x24d518), wait (0x24c4cc), the earlier set back (0x1e2bdc), while state + 2 is not 0. |
| 0x24d518, 0x24c4cc | Device mode: send isochronous packets on an endpoint; wait for the endpoint event. |
| 0xc75cc | `USBAudioTask`. |
| 0x132038 | The stream loop. Sends packets to endpoint 0x81. |
| 0x1323d8 | Handles SET_INTERFACE. Alternate setting 1 starts the stream. |
| 0x1e5b84 | iAP lingo 0x0A (Digital Audio) handler. |
| 0x1e61c0 | Returns 1 if the audio goes to USB. |

### USB host

Refer to [re/usb-host.md](../re/usb-host.md) and [USB-AUDIO-OUT.md](../USB-AUDIO-OUT.md). The test patch `usb-host-probe` (branch `usb-audio-out`) uses some of them. The facts are Static, except where the table gives Emulator.

| Address | Function |
|---|---|
| 0x6bc3dc | Class driver list (RAM 0x1083e138): pairs (driver record, dispatch table). |
| 0x6c8820 | UIM (host controller driver) dispatch table, version 6. |
| 0x97300 | UIM init. |
| 0xd4820, 0xd4828 | Isochronous endpoint create and transfer: stubs that return -1 (table words 0x6c885c, 0x6c8860). |
| 0xd1288 | Controller reset. Sets `USBMODE` (0xC50001A8) to 3 (host). |
| 0x2860e8, 0x28608c | Host start and host stop. Emulator: a call of 0x2860e8 runs 0x97300 and 0xd1288, and the menus continue to work. |
| 0x6c8730 | Hub driver dispatch table, "initialize device" entry (0xe7bc4). Dispatch format: version 0x1100, validate, initialize device, initialize interface, finalize, notify. |
| 0x6c878c | Storage driver dispatch table, "initialize interface" entry (0x10dd00). |
| 0x6bc3dc | Driver registry entries (44 bytes, pairs at +0x1c): Hub, two USBCompositeDevice1.6 records (one table at 0x6c85ec), SampleStorageDriver (interface class 8), ICAType4CameraDriver (vendor 0x04A9), PTPCameraDriver (class 6/1/1). Emulator: the hub driver gets the simulated root hub 05AC:8031. |
| 0xcd430 | Piezo tone (period, duration in microseconds): a type-0 message to the queue 0x15 of `AsyncPiezo` (0x285060). Returns 1 if the buffer of 15 notes is full (the note is lost). Hz = 91225 / period. The firmware uses 0xb4 (507 Hz) and 0x90 (634 Hz) with 200000. Refer to [re/piezo.md](../re/piezo.md). |
| 0x285060 | `AsyncPiezo` task: puts each note in a ring buffer of 16 entries (RAM 0x10882314 periods, 0x10882354 durations, indexes at 0x1081dfb0). |
| 0xc719c | Piezo player: writes `period \| 0x80800000` to 0x7000a000 for each note. 0x11c750 writes 0 there when the buffer is empty (the piezo stops). |
| 0x1fb50c | iAP lingo 6 (USB host), command 3: tells the Camera Connector to switch on (1) or off (0). |
| 0x2856a4 | `USBPowerSense` task. |
| 0x97364 | In the UIM init: `bl 0x266794` (chip check 0x598: 1 if the chip ID byte at 0x70000000 is 0x32). The init stores (result == 0) at +0x60 of the controller object and, if it is 1, sets PFSC (force full speed) in PORTSC at 0x9746c. On the owner's iPod the result is 1 (no force). |
| 0x18a8d8, 0x18a870, 0x18a83c, 0x18a824, 0x18a888 | Interrupt object {u16 source, handler}: make; install and enable (returns the enable result); install only (manager method +0x48); method +0x34; disable and remove (0x127888, then 0x1277d0). The manager (0x127618) is an object outside the image (0x14936ad0). |
| 0x9741c | In the UIM init: install of the host USB interrupt handler 0xffd1c for source 20 (0x14). The device driver installs 0xcd8e0 for the same source (0x220e0c, literal 0x220ef0). Emulator: the device handler is installed after the start, also without VBUS. |
| 0xcb118 | Completion callback of a control transfer stage: (request \| stage bit, status, bytes, …). Status 0 is correct; 0xfffffff0, 0xffffe4ba and 0xffffe4c5 are errors. The stage flags are at request + 0x2c (0x1000000, 0x2000000, 0x4000000). Called by the UIM completion code 0xe01a0. |
| 0xd377c | "Add device" (Mac OS 9 USBExpertInstallDeviceDriver): logs "Add device: VID %d PID %d", refuses a hub (class 9) unless g[0] > 1 or (g[1] < 3 and (g[0] != 0 or g[1] == 0)), then scores each registry entry (0xc50ac) and calls the best driver's validate. Errors to 0xd9cec(4, code): 0x673/0x67d hub refused, 0x68c no driver, 0x69f driver failed. Only call: 0x10c1d8. g = RAM 0x1083e0f8 (g[0] is 0 from the start; g[1] counts the hubs). |
| 0xad80c | (size, clear): the memory of the UIM (frame list, queue head pool 0xe4238, transfer buffers). Calls 0x28ce4c with 16-byte alignment and clears the memory if the second argument is not 0. Real iPod and emulator: the addresses are in the window 0x90000000–0x94000000. The CPU and the controller use the same address. | Static, Emulator |
| 0xa7164 | Cache operation for a DMA buffer (address, length): `return 0`. It is empty. | Static |
| 0x9e2d4 | Physical address of a buffer: gives the same address back (1 range). | Static |
| 0xe5540 | Makes the periodic frame list: 4 KB from 0xad80c, 1024 words of 1 (terminate) at the controller object +0x44, PERIODICLISTBASE = the same address. A soft table of 1024 queue head pointers at +0x3c. | Static |
| 0xf5c80 | Insert an interrupt queue head into the periodic schedule. **Firmware bug:** the frame list word is (r1 + 0x34) \| 2, but the callers (0x9761c in 0x974ec, 0x96d14 in 0x96c44) give the queue head only in r0. Real iPod: the frame list pointed to the controller object +0x34 (a block of zeros). Static, Real iPod. UIM controller object (`*(0x1084a778 + 0xc)`): +0x3c the processor address of the first queue head of each frame, +0x44 the frame list. A queue head keeps its controller address at +0x34 (processor address \| 0x80000000), its software next at +0x30, its interval byte at +0x3c and its offset at +0x3d. Emulator: an empty frame list holds 1 (terminate) in each frame. |
| 0xc50ac | Driver score for "add device" (device descriptor, registry entry). 1000 if the vendor ID is equal to the record +8 and the entry is not in use. 100 if the device class is equal to the record +0x35, 110 if the subclass is also equal to +0x36, and 10 more if the protocol is equal to the u16 at +0xe. 0 if the record flags +0x3c have bit 2 and nothing matches. Static. |
| 0x6bc3dc | Class driver registry (44-byte entries: record, dispatch, +0x15 in use). Entries: hub (class 9), composite (class 0, record 0x1084a308), composite (class 2, record 0x1084a360), storage (class 8), ICA camera (vendor 0x04A9), PTP camera (class 6/1/1). No entry matches class 0xEF or an audio device. Static, Real iPod. |
| 0x108b6c | Composite driver validate: `mov r0, #0; bx lr`. It accepts each device. Static. |
| 0xcba54 | Completion callback of an interrupt transfer (request, status, bytes). Called by 0xcbfb8. The hub driver gives it with the status-change interrupt transfer. |
| 0xe7a50 | hubAddDeviceHandler: a state machine (+0x18) for a new device on a hub port. The completion callback drives it. |
| 0xe7980 | Root port status (port, &{wPortStatus, wPortChange}). Called at 0xd28f0 (root hub GET_STATUS) and 0x10e75c (status-change poll 0x10e6e0). |

### The camera

Refer to [re/firmware-camera.md](../re/firmware-camera.md). The iPod Video has
no camera. The firmware has the code of the camera of the iPod Photo. The code
came with the USB host stack of the Camera Connector of 2005. The facts are
Static.

| Address | Function |
|---|---|
| 0x6c8898 | The record of the driver of the camera of the type 4. The tag "usbd" at +0, the vendor 0x04A9 at +8, the name at +0x14. |
| 0x6c88f0 | The record of the driver of the camera of the protocol of the pictures. The class 6, the subclass 1 and the protocol 1 at +0x10. |
| 0x6c88d8 | The table of the methods of the driver of the camera of the type 4. The version 0x1100. The 5 methods: 0x113a78, 0x118514, 0x1190a4, 0x110868, 0x10d86c. |
| 0x6c8930 | The table of the methods of the driver of the camera of the protocol of the pictures. The 5 methods: 0x110620, 0x1174d8, 0x118b50, 0x10d580, 0x105c1c. |
| 0x113a78 | The type 4 driver accepts the device. It calls 0x11281c with the vendor and the product. |
| 0x11281c | The check of the product. It accepts the vendor 0x04A9 and 40 numbers of the product. It refuses 0x3042, 0x304a, 0x3053 and 0x3054. |
| 0x113aa4 | Makes the object of the device of the type 4. The 4 methods of the class are at 0xe74c0, 0xec968, 0x10fa48 and 0x10e2d0. |
| 0x118b50 | The pictures driver accepts an interface. The class at +5 must be 6, the subclass at +6 must be 1 and the protocol at +7 must be 1. It makes the object with 0x110780. |
| 0x10d86c | The type 4 driver starts the device. It does nothing if the operation is not 0x0b. It sends the notification 0x12 with the code 3. |
| 0x105c1c | The pictures driver starts the device. It sends the notification 0x12 with the code 3 and the code 2. |
| 0x0e74c0 | The method of the class that starts the session of the camera. The states are 8, 0x0b and 0x0e. |
| 0x0de9d8 | The method of the task `ICAPTPCameraIOTask`. It makes the task at the run time. The name is at 0x0deb4c. The priority is 0xc0 and the size of the stack is 0xc0. |
| 0x10a744 | Makes the buffer of the pictures. The buffer has 64000 bytes. |
| 0x100978 | Makes one request to the camera and reads the answer. It sends the data in parts of 0x1000 bytes. |
| 0xdd0dc | The task sends a request and waits for the answer. |
| 0xd5f64 | The task reads the answer of the stack. |
| 0xe0b2c | Reads the information of one object of the camera. The record has 0xa4 bytes. |
| 0x199f70 | The method of the task `PhotoCopyTask`. The name is at 0x199ff8. The size of the stack is 8. |
| 0x16c588 | The name of the device of the capture. The string "Image Capture device" is at 0x16c5f8. |
| 0x197e70 | The state of the import of the pictures. It gives 1 for the states 1 to 5 and for the state 7. |
| 0x211ddc | The name of each channel of the application. The channels of the pictures are 0x0d, 0x0e, 0x10, 0x17, 0x18 and 0x1b. |

### The USB device

Refer to [re/firmware-usb.md](../re/firmware-usb.md). The iPod Video is a USB
device. The firmware has the stack of the device of the Mac OS 9 USB family of
Apple. The facts are Static.

| Address | Function |
|---|---|
| 0x15fe28 | The table of the registers of the controller. The address of each register and the mask of each register. |
| 0x15fd30 | Fills the 34 words of the registers of the object of the controller. |
| 0x15fe6c | Writes one register. It does nothing if the value is the same. |
| 0x221278 | Makes the object of the controller. The interrupt object is at +0x104. |
| 0x24d628 | Makes the object of the interface of the USB. It makes 4 objects of interfaces. |
| 0x24d1f0 | Writes the number of the vendor of the device. The number is at +8 of the object. |
| 0x24d1c0 | Writes the number of the product of the device. The number is at +0xa of the object. |
| 0x24d1a4 | Writes the version of the device. The version is at +0xc of the object. |
| 0xd85d8 | Gives the identity of the iPod to the computer. The number of the vendor is 0x05ac. The number of the product tells the model. |
| 0xd86b4 | The numbers of the product: 0x1202, 0x1203, 0x1204, 0x1205, 0x1206, 0x1207, 0x1209, 0x120a. |
| 0xcd06c | Makes the descriptor of the device. The descriptor has 18 bytes. |
| 0xe5f84 | Makes the descriptor of a configuration. |
| 0xc0bb4 | Answers the requests of the computer. The type of the request is the byte at +0 of the message. |
| 0xe34f8 | The state machine of the device. The states are 1 to 4. |
| 0x170fec | Makes the object of the task `USBDeviceTask`. The name is at 0x17107c. The size of the stack is 0x20, the priority is 0x1000. |
| 0x170f2c | The method of the task `USBDeviceTask`. The loop calls the start, the session and the stop of the device. |
| 0x18472c | Makes the object of the task `USB MSC`. The name is at 0x184824. The size of the stack is 0x11. |
| 0xb95a4 | The task of the mode manager of the USB. The modes are the idle, the device and the host. |
| 0x184aec | Makes the object of the mode manager. |
| 0x184860 | Starts a mode. The function starts the mode only from the mode 0. |
| 0x18482c | Stops a mode. The function starts the mode 0 again. |
| 0x284338 | The method of the task `AccessoryDetectTask`. |
| 0x284eb0 | The method of the task `HPhoneDetTask`. It reads the state of the headphones. |
| 0x284f90 | The method of the task `OptoTask`. It reads the sensor of the click wheel. |
| 0x28558c | The method of the task `SerialOptoTask`. It reads the sensor of the serial port. |
| 0x28564c | The method of the task `TopPlugTask`. It reads the accessory of the plug. |
| 0xfebf8 | The method of the task `RsistrAccsryMgr`. It reads the resistance of the accessory of the click wheel. |
| 0x266034 | The state of the accessory of the resistor. It gives 0, 1, 3 or 100. |
| 0x1fb50c | Sends the command of the lingo 6 of iAP. The command 3 tells the accessory to change to the host mode. |
| 0x1242b8 | Makes an iAP message and puts it into the queue of the accessory. |
| 0x1d62d4 | Makes the thread of the incoming data of iAP. The name is at 0x1d6410. |
| 0x1d73e4 | Makes the thread of the outgoing data of iAP. The name is at 0x1d7520. |

### The user interface

Refer to [re/firmware-ui.md](../re/firmware-ui.md). The screens of the iPod are
not in the code. They are in the resources of the image. The code holds the
classes that read the resources. The facts are Static.

| Address | Function |
|---|---|
| 0x331da0 | The main block of the resources. The 8 sections. |
| 0x336188 | The table of the `Type` section. 158 entries. |
| 0x3368f0 | The table of the `View` section. 619 entries. |
| 0x333128 | The table of the `Menu` section. 40 entries. |
| 0x333308 | The table of the `Str ` section. 991 entries. |
| 0x331e2c | The table of the `BMap` section. 403 entries. |
| 0x653048 | The base of the offset of the table of a class in a `Type` resource. |
| 0x66a904 | The table of the class of the screens. 11 slots. 39 types use it. |
| 0x66a938 | The table of the class of the screens. 8 slots. 57 types use it. |
| 0x66a920 | The table of the class of the screens. 4 slots. 16 types use it. |
| 0x668250 | The table of the class of the empty element. 8 slots. |
| 0x168938 | Reads the `Type` section and registers the class of the screen. |
| 0x16914c | Makes the object of a screen of a class. |
| 0x21a168 | Registers a class. It looks up the class of a type. |
| 0x21f3dc | Looks up a name in the registry of the modules. |
| 0x21f254 | Looks up a name in the list of the children of an object. |
| 0x1fc128 | Makes the object of the engine of the screen. The name is at 0x1fc220. |
| 0x170bc8 | Makes the task `WindowManager`. The name is at 0x170c5c. |
| 0x155e7c | Makes the task `SearchHelperThread`. The name is at 0x155ed0. |
| 0x141060 | Makes the object of the empty element. |
| 0x141184 | Reads the element of the tag `enoN`. The tag is at 0x1411fc. |
| 0xab7f0 | Reads the element of the tag `paMB`. The tag is at 0xab8a4. |
| 0xa6bd0 | Reads the element of the tag ` rtS`. The tag is at 0xa6d28. |
| 0x12f150 | Reads the element of the tag `warD`. The tag is at 0x12f1a0. |
| 0x16c080 | Reads the element of the tag `ltnC`. The tag is at 0x16c0e8. |
| 0x10d278 | Reads the element of the tag `mTtD`. The tag is at 0x10d2b0. |
| 0x16c328 | The method of the class of the control. The type is at +4 of the object. |

### The modules of the screen

Refer to [re/firmware-modules.md](../re/firmware-modules.md). The table of the
modules is in the resource section of the image. The facts are Static.

| Address | Function |
|---|---|
| 0x79474 | The record of the module `OpenGLES`. The module has 179 methods. |
| 0x79784 | The record of the module `Filesytem`. The module has 4 methods. |
| 0x797d8 | The record of the module `Audio`. The module has 61 methods. |
| 0x79910 | The record of the module `Metadata`. The module has 152 methods. |
| 0x79bb4 | The record of the module `AsyncFileIO`. The module has 17 methods. |
| 0x79c3c | The record of the module `InputEvents`. The module has 2 methods. |
| 0x79c88 | The record of the module `Settings`. The module has 3 methods. |
| 0x7947c | The name "OpenGLES". |
| 0x7978c | The name "Filesytem". |
| 0x797dc | The name "Audio". |
| 0x79918 | The name "Metadata". |
| 0x79bb8 | The name "AsyncFileIO". |
| 0x79c40 | The name "InputEvents". |
| 0x79c8c | The name "Settings". |
| 0x13061973 | The magic of a record of the table of the modules. |

### The library of C

Refer to [re/firmware-library.md](../re/firmware-library.md). The library is
the code of the compiler of Apple. The facts are Static.

| Address | Function |
|---|---|
| 0x7ca44 | `memcmp`. It compares 2 blocks of bytes. |
| 0x7cae0 | `memcpy`. It copies a block of bytes. |
| 0x7cad0 | `memset`. It fills a block with 1 byte. |
| 0x7cc48 | `memmove`. It copies a block of bytes. |
| 0x7ccd0 | `memset`. It fills a block with 0. |
| 0x7cd28 | `strncpy`. It fills the rest of the block with 0. |
| 0x7cd6c | `strcpy`. It copies a string. |
| 0x7cdd4 | `strncmp`. It compares 2 strings. |
| 0x7ce4c | `strncpy`. It copies a string of a number of bytes. |
| 0x7ceb8 | `strlen`. It returns the length of a string. |
| 0x7cfdc | `strcmp`. It compares 2 strings. |
| 0x7d018 | `__di3di3`. It divides 2 numbers of 64 bits. |
| 0x7d024 | `__udivsi3`. It divides 2 numbers of 32 bits. |
| 0x7d1c4 | `__aeabi_fmul`. It multiplies 2 numbers of 32 bits with a fraction. |
| 0x7d1f0 | `__floatundisf`. It changes a number of 32 bits into a number with a fraction. |
| 0x7d284 | `__aeabi_ldivmod`. It divides 2 numbers of 64 bits. |
| 0x7d394 | `__floatdidf`. It changes a number of 64 bits into a number of 32 bits with a fraction. |
| 0x7d4f4 | `__floatdisf`. It changes a number of 32 bits with a fraction into a number of 64 bits. |
| 0x7d578 | `__floatdisf`. It changes a number of 32 bits with a fraction into a number of 64 bits. |
| 0x7d5c8 | `__aeabi_fadd`. It adds 2 numbers of 32 bits with a fraction. |
| 0x7d69c | `__aeabi_fmul`. It multiplies 2 numbers of 32 bits with a fraction. |
| 0x7d774 | `__aeabi_fcmp`. It compares 2 numbers of 32 bits with a fraction. |
| 0x7d7b4 | `__aeabi_fdiv`. It divides 2 numbers of 32 bits with a fraction. |
| 0x82694 | `__umodsi3`. It gives the rest of the division of 2 numbers of 32 bits. |
| 0x7a794 | `malloc`. It asks for a block of a number of bytes. |
| 0x7a7b0 | `free`. It gives a block back. |
| 0x7a6b0 | `realloc`. It changes the size of a block. |
| 0x7a6fc | `calloc`. It asks for a block and fills it with 0. |

### The power and the hardware

Refer to [re/firmware-power.md](../re/firmware-power.md). The power comes from
the power chip of the PP5020 of Apple. The facts are Static.

| Address | Function |
|---|---|
| 0x284374 | The method of the task `AlarmTask`. The events are 0x89, 0x8a, 0x8b and 0x94. |
| 0x28453c | The method of the task `BacklightTask`. The events are 0xa6 to 0xa9. |
| 0x284a54 | The method of the task `CNATask`. The iPod Video has no modem. |
| 0x284f30 | The method of the task `HoldSwitchTask`. It reads the switch with 0x2651dc. |
| 0x284a18 | The method of the task `LowBattDebounceTask`. |
| 0x284ff4 | The method of the task `PCFPowerMgr`. It calls the kernel with the number 0x18 at the end. |
| 0x285460 | The method of the task `RTCTimerMgr`. The records of the timers have 0x14 bytes. |
| 0x2856f0 | The method of the task `WatchdogTask`. It calls the software interrupt 0x123456 if the memory for the table is not there. |
| 0x148108 | Makes the object of the manager of the power. The name is at 0x14815c. |
| 0x281b4c | Fills the table of the pins of the general purpose input and output. The table is at 0x281f00. |
| 0x281f00 | The table of the pins. The 5 registers are 0x6000D000, 0x6000D080, 0x6000D0EC, 0x6000D100 and 0x6000D154. |
| 0x1b73c8 | Makes the object of the power management unit. The object has the address 0x70000034 at +8. |
| 0x1b741c | The word with the address 0x70000020. The function 0x1b73c8 sets the bit 0x40000000. |
| 0x1c7f58 | Makes the object of the clock of the system. The object has the address 0x70000020 at +0xc. |
| 0x265164 | Returns the hardware version `HwVr`, read one time from + 0x84 of the object of 0x2827b8 and kept at 0x1081de40 + 0x28. The 16 high bits are the generation (0xb is the iPod Video). The 16 low bits are the board revision: 0xb0005 on a 5G, 0xb0011 on a retail 5.5G. It is not a measurement. Refer to [re/search-5g.md](../re/search-5g.md). |
| 0x2657fc | Gives the state of the power. The function gives 1 when the channel is 10, 11 or 12. |
| 0x265820 | Gives the state of the charger. The function gives 1 when the channel is 5, 6, 8 or 9. |
| 0x265a74 | Gives the state of the battery. The function gives 1 when the channel is 10, 11 or 12. |
| 0x264fa4 | Gives the state of the power. The function has a switch with the cases 4 to 0xc. |
| 0x265abc | Gives the state of the audio. The function has a switch with the cases 4 to 0xc. |
| 0x1ae774 | Selects the element of the battery view (View 25599): the icon value + 4, or 0x1b for the text 0x63fc. Refer to [re/battery.md](../re/battery.md). |
| 0x1d91dc | UI timer handler: reads the battery icon value at 0x1d91f8 (0x1e7fe4) and marks the status elements. The patch `battery-log` hooks 0x1d91f8. | Static, Patch |
| 0x1ae6d0 | (view, index): makes one child of the battery view visible, with method + 0x9c. One caller: 0x1ae6b8. |
| 0x1ebfec | Reads the switch byte 0x1081dfe3 (`_show_voltage`). If it is set, marks the battery text 0x63fc for a new draw. |
| 0x21a168 | (view, Type record, gc, out): applies a text style. Type + 0 is the font `Str` ID, + 4 the size, + 8 the colour. Static. |
| 0x243fb0 | (label, parent, Type ID): gives a label a text style. Static. |
| 0x1d3ac4 | Reads the hidden switch files in `iPod_Control/Device/`. Refer to [re/device-switches.md](../re/device-switches.md). |
| 0x175818 | Reads the state of the battery and the state of the charger. The states are at +0x1bc and at +0x1be. |
| 0x2823bc | Starts the driver of the general purpose input and output. |
| 0x1fcf50 | The table of the clock. The table has 11 registers from 0x60004000 to 0x60004030. |
| 0x1fca88 | Copies the table of the clock into the registers. |
| 0x28578c | The string "watchdog: Could not allocate timer!". |
| 0x2857bc | The string "watchdog: No registered handlers for ". |

### The music and the media

Refer to [re/firmware-media.md](../re/firmware-media.md). The video is decoded by
the video processor of Broadcom. The facts are Static.

| Address | Function |
|---|---|
| 0x205cfc | Makes the task `ArtworkLoadTask`. The stack is 0x20, the priority 0x8000. The name is at 0x2aa7fc. |
| 0x16b0b0 | Makes the task `MP3ExampleTask`. The stack is 0x10, the priority is the value at 0x16b0fc << 4. The name is at 0x16b104. |
| 0x199f70 | Makes the task `PhotoCopyTask`. The stack is 8. The name is at 0x199ff8. |
| 0x158124 | Makes the thread `TcMemManagerThread`. The name is at 0x158260. |
| 0x9483c | Makes the task `TrackCacheReadTask`. The stack is 8, the priority 0x2000. The name is at 0x94974. |
| 0x165164 | Makes the task `VCUpdateTask`. The stack is 0x20, the priority 0x800. The name is at 0x16522c. |
| 0x1419f4 | Makes the task `VideoDaisyTask`. The stack is 0x20, the priority 0x1000. The name is at 0x500c98. The method is at 0x14165c. |
| 0x1ddc50 | Makes the 2 tasks of the copy of the stream. The names are at 0x1ddc88 and 0x1ddc8c. |
| 0x20be1c | Makes the task `StreamCacheReadTask`. The stack is 8, the priority 0x4000. The name is at 0x20be64. |
| 0x1f9754 | Reads the statistics of the video processor. The value 0 is the audio and the value 1 is the video. |
| 0x1f996c | The name "mp_get_stats video". |
| 0x1f9980 | The name "mp_get_stats audio". |
| 0x1f9994 | The names of the statistics of the video processor. There are 22 names. |
| 0x287664 | Sends a command to the video processor. |
| 0x287250 | Reads a value of the statistics. |
| 0x1ca110 | The names of the boxes of the MP4 for the video. |
| 0x1ca758 | The names of the boxes of the MP4 for the audio. |

### The storage and the file system

Refer to [re/firmware-storage.md](../re/firmware-storage.md). The iPod has a
disk with an ATA bus. The facts are Static.

| Address | Function |
|---|---|
| 0x186b34 | Makes the 2 tasks of the bus of the disk. The stack is 0xc0, the priority 0x800. The names are at 0x186bbc and 0x186bd0. |
| 0x17775c | Makes the task `DiskReaderTask`. The stack is 8, the priority 0x800. The name is at 0x1777b4. |
| 0x284b0c | The method of the task `DiskMgrTask`. The table of the states of the partitions has 0x2d entries. |
| 0x34dec | The dispatcher of the file systems. It takes 6 arguments. It uses the 3 names of the table at 0xc26d8. |
| 0xc26d8 | The names of the file systems FAT12, FAT16 and FAT32. Each name has 8 bytes. |
| 0x176c14 | The name HFSPLUS in the table of the DRM. |
| 0x212b68 | The name "Disk Activity". |
| 0x213dcc | The name "Disk Spinup". |
| 0x213dd8 | The name "Disk Spindown". |
| 0x213de8 | The name "Disk Obtain Access". |
| 0x213dfc | The name "Disk Release Access". |
| 0x177038 | The name "ForcedDiskMode". |
| 0x17704c | The name "BangFolder". |
| 0x177058 | The name "CorruptDataPartition". |
| 0x177070 | The name "CorruptFirmwarePartition". |

### The file systems

Refer to [re/firmware-filesystems.md](../re/firmware-filesystems.md). The
firmware has the code of the FAT and the code of the HFS+. The facts are
Static.

| Address | Function |
|---|---|
| 0xc22b4 | Reads the table of the partitions of the disk. It reads 4 partitions. It gives the type of the file system of each partition. |
| 0x93c4 | Reads the header of the volume of the HFS+. It looks for the 2 signatures. |
| 0x95a0 | Reads the header of the volume of the HFS+. |
| 0x96c0 | The signature "Standard_Eta" of the volume of the HFS+. |
| 0x96d0 | The signature "STANDARD" of the volume of the HFS. |
| 0x9da4 | Changes the byte order of a 32 bit number. |
| 0x9dd8 | Changes the byte order of a 32 bit number. |
| 0x9e0c | Changes the byte order of a 32 bit number. |
| 0x9e34 | Reads the record of the tree of the catalog. |
| 0x9e9c | Reads the record of the tree of the catalog. |
| 0x9f1c | Reads the record of the tree of the catalog. |
| 0x9f70 | Reads the record of the tree of the catalog. |
| 0x9ff4 | Reads the record of the tree of the catalog. |
| 0xa08c | Reads the record of the tree of the catalog. |
| 0xa130 | Reads the record of the tree of the catalog. |
| 0xa1ec | Moves the pointer of the record by a number of bytes. |
| 0xa204 | Moves the pointer of the record by a number of words. |
| 0xa21c | Moves the pointer of the record by a number of 16 bit values. |
| 0xa23c | Moves the pointer of the record by a number of 32 bit values. |
| 0xa260 | Moves the pointer of the record by a number of values. |
| 0xa288 | Moves the pointer of the record by a number of values. |
| 0xa6e4 | Changes the 4 words of 4 bytes with a table of 256 bytes. |
| 0xa720 | Changes the 4 words of 4 bytes with a table of 256 bytes. |
| 0xa75c | Changes the order of the bytes of a value. |
| 0xa7c0 | Changes the order of the bytes of a value. |
| 0xa824 | Changes the value with a table. |
| 0xa988 | Changes the value with a table. |
| 0xab18 | Changes the 4 words of 4 bytes with a key of 16 bytes. |
| 0xab58 | Changes the 4 words of 4 bytes with a key of 16 bytes. |
| 0xac40 | Changes the 4 words of 4 bytes with a key of 16 bytes. |
| 0xad24 | Changes the 16 bytes of a key with a key. |
| 0xade0 | Changes the 16 bytes of a key with a key. |
| 0xaedc | Makes the object of the node of the tree. |
| 0xaf8c | Reads the record of a file of the catalog. |
| 0xb104 | Reads the record of a file of the catalog. |
| 0xb27c | Reads the record of a folder of the catalog. |
| 0xb54c | Reads the record of a folder of the catalog. |
| 0xb800 | Reads the node of the tree of the catalog. The 2 kinds of the node are 0x44332211 and 0x11223344. |
| 0xb8c8 | Reads the kind of the node of the tree of the catalog. |
| 0xb9a0 | Reads the name of a record of the catalog. |
| 0xbaf0 | Reads the data of a record of the catalog. |
| 0xbf00 | The first kind of the node of the tree. The value is 0x44332211. |
| 0xbf04 | The second kind of the node of the tree. The value is 0x11223344. |
| 0xbf18 | Reads the header of the volume of the HFS+. |
| 0xc034 | Reads the header of the volume of the HFS+. The object of the volume has 0x250 bytes. |
| 0xc140 | Reads the node of the tree of the volume. |
| 0xc264 | Reads the node of the tree of the volume. |
| 0xc300 | Looks for a name in the catalog. |
| 0xc408 | Looks for a name in the catalog. |
| 0xc510 | Looks for a name in the catalog. |
| 0xc628 | Looks for a name in the catalog. |
| 0xc744 | Looks for a name in the catalog. |
| 0xc868 | Looks for a name in the catalog. |
| 0x7100 | Copies the clusters of the FAT. |
| 0x7278 | Changes the bytes of a value with the cipher of the FAT. |
| 0x7c14 | Copies the clusters of the FAT. |
| 0x7d84 | Reads a record of the directory of the FAT. |
| 0x7f3c | Reads a record of the directory of the FAT. |
| 0x8140 | Reads the file of the FAT. The function has 24 arguments. |
| 0x8a48 | Reads the file of the FAT. The function has 24 arguments. |

### The JavaScript engine

| Address | Function | Evidence |
|---|---|---|
| 0x135b2c | Bytecode interpreter (SpiderMonkey 1.5). Reads one opcode byte. Uses the opcode table at `DAT_00136a6c`. | Static, Emulator |
| 0x135b84 | The instruction that has the bytecode address in r0 for each opcode. | Emulator |
| 0x120bf0 | Calls a native method from a script. | Static |

Evidence for SpiderMonkey:

- 0x80000001 is `JSVAL_VOID`.
- The masks 0x3ffffffe and 0xc0000001 agree with the SpiderMonkey tagged values.
- The opcode numbers agree with the SpiderMonkey 1.5 opcode table, for example 0x06 `GOTO`, 0x07 `IFEQ`, 0x35 `GETPROP` and 0x3A `CALL`.
- The opcode table (`JSCodeSpec`) is at RAM address 0x1083de9c.

The firmware does not contain JavaScript source text, or the names "SpiderMonkey" or "Mozilla".

### The games

Refer to [re/games.md](../re/games.md). The iPod reads the games from the folder `iPod_Control/games_RO`. A game runs only on an iPod that has the file `iPod_Control/iTunes/IC-Info.sidb` of the account that bought the game. The app copies that file as it is. This project does not research the protection of the games.

| Address | Function | Evidence |
|---|---|---|
| 0xd9d30 | (n): the name of a games folder. 0 = `games_RO`, 1 = `gamedata_RW`, 2 = `gamestats_WO`, 3 = `gamedata_ShareRW`. The names are at 0x2a9c3c. | Static |
| 0xdeff4 | (path, n, name, format): the full path of a games folder. The formats are `iPod_Control/%s/%s%s%s` at 0xdf0a8 and `iPod_Control/%s%s%s` at 0xdf094. | Static |
| 0x24d88c | Makes the object of the games. The object is at 0x108711d4. | Static, Emulator |
| 0x24d9f8 | (games): scans the folder of the games. It reads the directories. It sets the state of the scan to 3. | Static |
| 0x24d7c0 | (games, path, game): makes the list of the games. It sets the state of the scan to 2. | Static |
| 0x24dca0 | (games, n): 1 if the game n is in the list. The count is at most 0x5b (91). | Static |
| 0x24dce8 | (games): makes the list of the games. It reads the directory. | Static |
| 0x24d918 | (games, type, n, value): makes one item of the list of the games. | Static |
| 0x24df00 | (games, size): checks the files of the game. It has 7 steps. It counts the steps that passed at the offset 0x244. | Static |
| 0x24e074 | (games): frees the resources of the steps that failed. It uses the counter at the offset 0x244. The switch is at 0x24e080. | Static |
| 0x1314ec | (game): reads the manifest of the game. It returns 0 when the manifest is good. | Static |
| 0x24e37c | (games): checks the platform of the game. It reads the `Platforms` array. It returns 0 when the game is valid, 0xffffff01 when the platform is not on the iPod and 0xffffff02 when the platform has no executable. | Static |
| 0x24e554 | (games): the loop of the scan. It calls 0x24d9f8, 0x24e66c, 0x24de30, 0x24e0dc, 0x24dde8, 0x24db38, 0x24e64c and 0x24dc24. | Static |
| 0x24e66c | (games): checks the game and starts it with 0x1d32e0. It runs only in the state 3. | Static |
| 0x24e718 | (games, ...): the task of the scan. It makes the list of the platforms and the list of the games. | Static |
| 0x24d87c | The loop of the scan in a task. | Static |
| 0x24e9c0 | Draws the screen of the games. | Emulator |
| 0x24dc0c | (games, state): sets the state of the scan. It accepts the values 1 to 10. | Static |
| 0x12e3cc | The handler of the screen of the games. It starts the scan. | Static |
| 0x12dd80 | The handler of the screen of the games when it closes. | Static |
| 0x105a04 | (label): the bit of a main-menu item. The bit for the games is not known yet. | Static |
| 0x1d32e0 | Starts a game. The function 0x24e66c calls it. | Static |
| 0x24d99c | Starts the scan of the games. | Static |
| 0x24db38 | (games): waits for the state 7. It sets the state to 9. | Static |
| 0x24dc24 | (games): waits for the state 10. It sets the state to 1. | Static |
| 0x24dde8 | (games): waits for the state 6 or 3. It sets the state to 7. | Static |
| 0x24de30 | (games): waits for the state 4. It sets the state to 5 or 6. | Static |
| 0x24e074 | (games): makes the list of the games. | Static |
| 0x24e0dc | (games): the run of a game. | Static |
| 0x24e1e8 | (games): waits for the state 1 or 10. | Static |
| 0x24e4b4 | (games): waits for the state 1. | Static |
| 0x24e5d0 | (games): waits for the state 3. | Static |
| 0x24e64c | (games): a step of the loop of the scan. | Static |
| 0x11554c | Parses a property list. The function 0x24e240 calls it for the manifest. | Static |
| 0x256610 | (path): reads a file. The function 0x24e240 calls it for the manifest. | Static |
| 0x1222c4 | Reads a list of a key of the settings. | Static |
| 0x131bc8 | Makes the object of the manifest of a game. | Static |
| 0x193470 | (settings, label): 1 if the main-menu item is on. | Static |

The names of the folders of the games:

| Address | Name | Use |
|---|---|---|
| 0x2a9c3c | `games_RO` | The game files. |
| 0x2a9c48 | `gamedata_RW` | The data of the games. |
| 0x2a9c54 | `gamestats_WO` | The scores of the games. |
| 0x2a9c64 | `gamedata_ShareRW` | The data of the games for the shared mode. |
| 0x6788bb | `iPod_Control/games_RO/` | The path of the games. |
| 0x6788d2 | `Manifest.plist` | The manifest of a game. |
| 0x678ddd | `Manifest.plist.p7b` | The signature of the manifest. |

The keys of the manifest of a game are at 0x678d49. The keys are `GUID`, `BuildID`, `PlatformID`, `PlatformVersion`, `ExecutablePath`, `LaunchingArtwork`, `BuildIdentifier`, `Files`, `LocalizedNames` and `Platforms`.

The string `GamesPlatformID` is at 0x177100. The string `GamesPlatformVersion` is at 0x177110. The function `FUN_00175c74` at 0x175c74 gives these two values to the computer.

The word `Games` is in the JavaScript of the user interface at 0x4b145c, 0x4b38f2, 0x4b3b44 and 0x4b4308. The word `Resume Game` is at 0x4b14d8.

The name of the folder of the games is in the osos in small letters: `games_RO`, `gamedata_RW`, `gamestats_WO` and `gamedata_ShareRW`. The program of iTunes for macOS 11.4 uses the same folders with a capital letter: `Games_RO`, `GameData_RW` and `GameStats_WO`. The file system of the iPod is FAT and it keeps the case of the names.

The manifest of a game has an array `Files`. The array has 2,528 entries in the 56 games of the archive. Each entry has a `Path`, a `Size` and a `Digest`. The `Digest` has 40 hexadecimal characters. The digest is not the SHA-1 of the file. The algorithm of the digest is not known yet. The `PlatformID` is 1 in all 56 games. It is 2 in 49 games, 3 in 49 games and 4 in 11 games.

The firmware finds a game by the name of its folder in the directory `games_RO`. The function `FUN_0024e240` at 0x24e240 calls `FUN_000deff4` at 0xdeff4 to build the path `iPod_Control/games_RO/<name>/Manifest.plist`. The function `FUN_000d9d30` at 0xd9d30 gives the name of the folder by the number. The number 0 gives `games_RO` at 0x2a9c3c. The function `FUN_0024dce8` at 0x24dce8 reads the directory. The function `FUN_0024d918` at 0x24d918 makes one item of the list of the games. The item has the name of the entry of the directory. The firmware does not compare the name of the folder with the GUID of the manifest. The 55 games of the archive have the same name for the two. The game `1B200` has the GUID `1b200` in the manifest and the name `1B200` for the folder.

The function `FUN_0024df00` at 0x24df00 checks the files of a game. The function has 7 steps. The function counts the steps that passed. The counter is at the offset 0x244 of the object of the games. The counter starts at 7. The counter goes down by 1 for each step that passed. The counter keeps the value of the step that failed.

The strings of the games are in the language blocks of the resources. The string -511 is "This game cannot be played." at 0x4b2b18. The string -512 is "Connect your iPod to iTunes and reinstall the game." at 0x4b2ae4. The string -508 is "This version of the game is no longer supported." at 0x4b2bbc. The string -509 is "Connect your iPod to iTunes and download the latest version." at 0x4b2b7c. The string -510 is "For additional information, please visit http://apple.com/support/ipod/" at 0x4b2b34. The string -513 is "This may be the result of a full iPod." at 0x4b2abc. The string -514 is "For more information, please visit http://apple.com/support/ipod/" at 0x4b2a78. The table of the ids of the English language is at 0x2aca34. The entry of the string -511 is at 0x2aca40.

The function `FUN_0024df00` shows the View 0x66000006 when the counter is 7. The function shows the View 0x66000007 when the counter is any other value. The View 0x66000006 is at 0x4e5a18. The View 0x66000007 is at 0x4e5a74. The data of the ids is at 0x24e06c and at 0x24e070.

The four names of the folders of the games are in the data area. The function `FUN_000d9d30` at 0xd9d30 gives the name by the number. The function uses the table of the pointers at 0xd9d64. The names are `games_RO` at 0x2a9c3c, `gamedata_RW` at 0x2a9c48, `gamestats_WO` at 0x2a9c54 and `gamedata_ShareRW` at 0x2a9c64. The game runs in the task `eAppMotor` (the name is at 0x24e7fc). The function `FUN_0024e718` at 0x24e718 makes this task. The function `FUN_001d32e0` at 0x1d32e0 starts the game. It gives a message to the application object at the RAM address 0x1081da80.

## Vtables and classes

| Address | Content |
|---|---|
| 0x66e470 | Slot of the draw method of the list-row label (0x1bb260). |
| 0x677a14 | Slot of the draw method of the general label (0x244924). |
| 0x66b4dc | Vtable of a list cell. The parent of a label in a list row has this class. |
| 0x66b298 | Vtable of a plain view. The parent of a label in Now Playing has this class. |
| 0x66d89c | Vtable of a picture view (for example the ">" arrow). |
| 0x66c8c0 | Vtable of the Settings controller. |
| 0x668f1c | Vtable of the language manager (made by 0x152a6c). + 0x10: the parent, the root object with the main block. + 0x14: the map from the four-character code to the provider. + 0x3c: the current code. + 0x40: the current provider. |
| 0x66dddc | Vtable of the base class of the language manager and of the root object (0x1aeaa0). |
| 0x66c94c, 0x66c950 | Slots of the "get" and "set" methods of the settings object. |
| 0x670720 | Vtable of the power controller. +0x6c: display on/off. +0x70: sleep. +0xb4: external power. |
| 0x69fd2c | A table entry that points to the Sleep item handler 0x1d83fc. |
| 0x666920, 0x666958 | Vtables of the USB audio control and streaming objects. |
| 0x677290 | Vtable of a browse list (for example Albums and Artists). +0x30 (0x6772c0): event method 0x23b704. +0x138 (0x6773c8): set the selection. |
| 0x6701f0 | Slot of the UI event handler 0x1d81cc. |
| 0x66cad4 | Vtable of the play list. +0x0c: count (0x195ef4). +0x10: add songs at the end (0x19602c). +0x14: remove songs (0x195f58). +0x18: clear (0x196584). |
| 0x6775b8 | Vtable of a menu list. +0x140 (0x6776f8): `activate(list, row)` 0x23ca4c. The list has the Menu ID at +0x1c (i16) and the menu data at +0x144. |
| 0x66ec80 | Vtable of a menu item object. Item + 0x10 points to the Menu resource item + 4. |
| 0x66a510 | Vtable of the application object. +0x30: event method 0x1d3348. |
| 0x676974 | Vtable of a key event. +4: delete. +0x14: type check. |
| 0x677aec | Vtable of a wheel event. |
| 0x17ef8c | Literal (not a vtable): the damage callback 0x17ef98. |

## Object layouts

| Object | Offset | Content |
|---|---|---|
| View | +0x10 | Parent view |
| View | +0x1c | u16: the layout element ID. The data source of a list uses it to select the data. |
| View | +0x5c | Left edge |
| View | +0x74 | Graphics context |
| View | +0x78, +0x7c, +0x80 | Child list, count, array pointer |
| Graphics context | +0x10 | Byte: draw mode |
| Graphics context | +0x11, +0x15 | Colour and second colour (R, G, B, A) |
| Graphics context | +0x1c | The bitmap. The descriptor is at bitmap + 4. |
| Graphics context | +0x2c, +0x30 | x origin, y origin |
| Graphics context | +0x34 | Clip rectangle, in bitmap coordinates |
| Bitmap descriptor (bitmap + 4) | +0x00, +0x04 | Pixel pointer; stride in bytes |
| Bitmap descriptor | +0x08, +0x0c | Bits for each pixel (16); shift (x << shift is the bit offset) |
| Bitmap descriptor | +0x10 | u16: format (0x565, 0x555, 0x1444, 0x1888; bit 0x2000 swaps the bytes) |
| Bitmap descriptor | +0x14 … +0x20 | Bounds: top, left, bottom, right |
| Bitmap descriptor | +0x24 | The draw listeners (damage) |
| Rectangle | +0, +4, +8, +12 | top, left, bottom, right |
| Application object | +0x444 | Backlight time in seconds |
| Application object | +0x487 | "Sleep pending" flag |
| Application object | +0x3e4 | Power controller |
| Object of 0xaf698 and 0x88ff8 | +0xb78 | Maximum volume: 0x100, or 0xd8 with the EU limit |
| Keep-awake message | +0x18 | Time in ms (type 2) |
| Track | +0x28, +0x2c, +0x34, +0x3c, +0x40 | Pool indexes: title, artist, album, composer, genre |
| Track | +0x30 | Index of the artist sort key (pool db + 0x10c) |
| Music database | +0xb4, +0xe0, +0x138, +0x190 | String pools: titles, artists and composers, albums, genres |
| Music database | +0xd2c, +0xd14 | The open file `iPod_Control\Artwork\ArtworkDB` (0xa1ff0) |
| Track | +0x108, +0x10c | dbid (mhit + 0x70). ArtworkDB links an image to this ID. |
| Native browser | +0x00 | u8: 1 = main browser; 2 = it uses the main browser at +0xc9c |
| Native browser | +0x10, +0x228 | The selected artist row; the selected artist name (u16 length, UTF-16) |
| Native browser | +0xc48, +0xc4c, +0xc50 | Artists: string indexes (pool db + 0xe0), letter table, count |
| Native browser | +0xc60 … +0xc6c | Albums |
| Main browser | +0xcf8, +0xca0 | The track data (string pools); the settings and text compare data (+0xb50: "Compilations") |
| JS browser | +0x1c | The native browser |
| Track | +0x00, +0x04 | The database; the next track |
| Music database | +0x1c, +0x20 | Track count; the track array (0x110 bytes for each track) |
| String pool (`strc`) | +0x08, +0x10, +0x14 | Handle to the entries {offset, length}; handle to the UTF-16 text; entry count |
| Library | +0xcf0, +0xcf8 | A track list (0 while the Albums list shows); the database |
| Library | +0xc60, +0xc6c | The album list: the album pool index of each row of the Albums list (without "All"), in its order; the count |
| Library | +0xc48, +0xc50 | The artist list (artist pool), filled when the Artists list opens |
| Track list | +0x2fc + 4 × slot | Sorted array of items (the item at + 0x10 + 4 × i; item + 0x20 is the track). Slot 6: by album. |
| Main provider | +0x1c, +0xc0 … +0xdc | The library; the row counts of the browse lists |
| Track | +0x58, +0x6c, +0x70, +0x74, +0x76 | Length in ms, file size, sample rate (float), bit rate (kbps), year. Refer to [re/song-info.md](../re/song-info.md) for the other mhit fields. |
| Track | +0x7a, +0x8c, +0x94 | Rating, play count, last played |
| Play list (0x196418) | +0x04, +0x14, +0x18, +0x1c | The track list (count: u16 at (+0x28) + 0x32); the index of the current song; byte 1 if On-The-Go; the lock |
| Track | +0x8b | Bit 1: mhit + 0xa5. This is not the artwork flag (libgpod: mhit + 0xa4 "has artwork"). |
| View | +0x20 | Flags. (flags & 0x1800) == 0x800 if the view is visible. |
| Browse list | +0xa4 | An object. Its word at +0x14 is the selected row. |
| Browse list | +0xb8 | The number of rows |
| Event | +0x04, +0x0c, +0x10 | Type; wheel direction; key code in bits 16–23 |
| UI object | +0x44 | Byte: the count of keys down |
| Display server | +0x110 | Layer 0 (each layer has 0x90 bytes) |
| Display server | +0x6be, +0x6c0, +0x6c2 | Update: 1 = send rows; u16 first row; u16 end row |
| Display server | +0x6c4, +0x6c8 | The bound layer (0 between updates); the mutex |
| Display layer | +0x00, +0x04, +0x0c | Byte 1 if valid; the CPU framebuffer (RGB565, 320 × 240); the BCM surface (+0x10: stride 640) |

## RAM addresses

The physical address is 0x10000000 + the CPU address.

| Address | Content |
|---|---|
| 0x1081da18 | Pointer to the application object. |
| 0x1081da00 | The address of the heap object of the general allocator (`fw_alloc`). Heap object + 0x00: the free bytes; + 0x04: the used bytes; + 0x08: the count of allocations. Emulator (27 October 2026): 52.9 MB in total, 2.67 MB free with the Albums list. Refer to [../re/cover-flow.md](../re/cover-flow.md). |
| 0x1086bedc | Keep-awake slot flags (45 bytes). |
| 0x10870154 | The heap object of the general allocator. Emulator: the heap total is 55,519,024 bytes on 64 MB and 21,964,832 bytes on 32 MB (test patch at 0x13e8). About 3 MB stays free for all library sizes. |
| 0x10883614 | + 0x1b4: the start of the heap region; + 0x1b8: its size (0xa07b4). |
| 0x14983060 | The copy of the start struct (0x90 bytes). + 0x20: the RAM top. |
| 0x1086bf0c | Keep-awake time left in ms (45 words). 0xffffffff = always on. |
| 0x1081ff2c, 0x1081ff30, 0x1081ff34 | Power pin monitor objects (byte +6 is the saved pin state). |
| 0x108234ec | State of the USB audio streaming object. |
| 0x1081ee48 | Audio route state. |
| 0x108710dc | Device information object: +0x92 region code, +0x94 flags (bit 0 = EU volume limit). |
| 0x1083de9c | SpiderMonkey opcode table. |
| 0x108711d4 | The object of the games. The function 0x24d88c makes it. |
| 0x10882c3c | The display server. |
| 0x1081e0d4 | The layer index of the display (0). |
| 0x1081ec54 | Byte: the damage callback binds the layer if it is not 0. |
| 0x1081da80 | Pointer to the application object (class 0x66a510). |
| 0x1081d9c4 | The Clicker setting (a word): value 1 speaker, value 2 headphones, default 3. The default settings 0xf3dc0 write 3. The load 0xe1b64 copies it from the settings + 0xafc. 0x95f0c keeps it and clears value 2, and 0x99098 puts it back. |
| 0x1081e044 | Static guard of the shuffle seed (bit 0 = the seed is set). |
| 0x1081e048 | State of the shuffle generator (Park–Miller). |
| 0x1083e0ac | State of the card game generator. |
| 0x1081dae4 | State of C `rand()`. |
| 0x1081d9cc | Pointer to the play list object (vtable 0x66cad4). |
| 0x1081e07c | The audio object of the EQ messages is the word at + 0xc. |

The image ends at 0x7358c0. The region from 0x10800000 (8 MB) has the pool. No code refers to the area between the image end and 8 MB. The patches and the theme data use this area.

## Hardware registers

| Address | Name | Use |
|---|---|---|
| 0x60005010 | `USEC_TIMER` | Microsecond counter. `flash-wake-on-input` and `something-comforting` read it. |
| 0x7000a000 | `PWM0_CTRL` | The piezo: `period \| 0x80800000` plays a tone, 0 stops it. |
| 0x60006004 | `DEV_RS` | Device reset. 4 restarts the iPod. |
| 0x60006038 | — | Not in `pp5020.h`. A free-running 16-bit counter. 0x55c reads it two times for the shuffle seed. The emulator answers 0. |
| 0x6000d13c | GPIOL input value | Power pins: bit 0x08 (FireWire or charger, low = power), bit 0x10 (USB, high = power), bit 0x20 (not known). |
| 0x70000080 | `GPO32_VAL` | Bit 30 (0x40000000) switches the drive power (set = off). |
| 0xC30001E0–0xC30001FF | ATA taskfile | |
| 0xC30003F8 | ATA control | |
| 0x7000C000–0x7000C0FF | I²C controller | |

## Resource IDs

| Resource | Content |
|---|---|
| `TCmd` 9088 | The compiled JavaScript of the user interface (91,662 bytes at 0x4b441c). |
| Menu 24598 | The Settings menu. |
| Menu 24440 | The Music menu (10 items at 0x4af348). The Artists item has the label -126 and the value 0x41a2 at +0x0c. |
| Menu 24094 | The main menu (31 items). The label of each item is its key in the main menu mask, for example 0x5f7c = Artists. The UI script shows or hides each item. |
| Menu 24600 | Settings > Main Menu (28 rows). Each row has the settings key 0x6000 + the label of its main-menu item, for example 0x60005f7c for Artists. The rows under Music start with U+2003 U+2060. |
| Str -30 | "Artists": the title of the Artists screen. |
| View 24486 | The Artists screen (View 24484: the Albums screen). |
| Menu −138 | The Backlight Timer menu (data at 0x4b069c). |
| View 24069 | The root view of the screen. |
| View 24506 | The title bar. |
| BMap 24379 | The title bar picture. |
| BMap 24342, 24343 | The progress bar in Now Playing. |
| BMap 24351 | An 11 × 11 blue gradient in the rating row. It is not the fill of the stars. |
| BMap 24268 | The ">" arrow (8 × 11). |
| BMap 24273 | The speaker icon of the song that plays. |
| Str −4 | "iPod", the title of the main menu. |
| Str −139 to −145 | The Backlight Timer items. |
| Str 0x602e, 0x602f | "On" and "Off". |
| Str 0x6063–0x607b | The names of the languages in the Language menu, for example 0x6063 "English". The keys 0x6065, 0x6069, 0x606a and 0x606f have no name. |
| Str 0x7e00 | "Dark Mode" (added by the `dark-mode` patch). |
| Str 0x7e01, 0x7e02 | "Something Comforting" and "Play" (added by the `something-comforting` patch). |
| Str 0x7e06, 0x7e07, 0x7e08 | "USB-C Audio", "On (44.1 kHz)" and "On (48 kHz)" (added by the `usb-audio-out` patch). |
| Str 0x7e03, 0x7e04 | "Album Artists", and the indented row text in Settings > Main Menu (added by the `album-artists` patch). |
| Str 0x7e0a | The main menu item of `usb-audio-out`: "USB-C Audio: Off", "On", "44.1 kHz" or "48 kHz". Settings > Main Menu row key 0x60007e09. |
| Str 0x7e10 | "Album Mix", the 4th value of Settings > Shuffle (added by the `shuffle-album-mix` patch). |
| Str 0x7e11, 0x7e12 | The main menu item of `shuffle-album-mix` (version 1.2): "Shuffle: " and the value. The text of its Settings > Main Menu row: "Shuffle" (string −135). Row key 0x60007e13. |

## Element IDs

The emulator found these element IDs (view + 0x1c):

| Row | Element ID |
|---|---|
| Album in an album list (normal and highlighted) | 0x6421 |
| Song in a song list (normal) | 0x641f |
| Song in a song list (highlighted) | 0x641e |
| Playlist (normal and highlighted) | 0x6425 |
| Menu item | 0x301 |
| ">" arrow | 0x5ecc |
| Speaker icon in a song row | 0x63eb |
| The Albums list (the list view itself) | 0x6382 |
| The Artists list and the Playlists list (the list view itself) | 0x6387 |

## Settings keys

| Key | Item |
|---|---|
| 0x60006031 | Backlight Timer command. The values are 0x6032–0x603a. |
| 0x60006062 | Language. The value is the key of the Language menu item, 0x6063–0x607b. Refer to [re/languages.md](../re/languages.md). |
| 0x60006088 | Clicker |
| 0x600060b7 | Sound Check |
| 0x600060e0 | Dark Mode (added by iPodFirm) |
| 0x600060e4 | Something Comforting (added by the `something-comforting` patch). Not a 32-bit word in osos 1.3. |
| 0x600060e8 | USB-C Audio (added by the `usb-audio-out` patch) |
| 0x600060ec | Date & Time > Daylight Saving (Menu 24604). `up-next` 0.4 used this key by mistake. |
| 0x60007e05, 0x60007e09, 0x60007e13 | Settings > Main Menu rows of `album-artists`, `usb-audio-out` and `shuffle-album-mix` |
| 0x60007e0f | Hold Select (added by the `up-next` patch, since version 0.5) |

## Open questions

- The caller of the method + 0x6c of the language manager after a selection in the Language menu. Is a call of 0x192ca8 safe in the lookup hook? Refer to [re/languages.md](../re/languages.md#open-questions).
- The function that gives the current time of day. A timed dark mode needs it.
- The style of the rating stars in Now Playing. The table at 0x336190 gives a style object (0x192448 + 16 × n) for each Type ID.
- Why the stock firmware defers Sleep after a computer session.
- The path of a long push of Play.
- The key code 0x6e: the emulator gives it for the button `menu`, but the note on 0x1d8570 says "a long push of Play". A test on the real iPod can answer which is correct.
- The function of the audio route flags at 0x1081ee48 + 0 and + 1.
- The UIM interrupt handler that completes the periodic USB host transfers.
- The cause of the empty artwork frame in Now Playing with the unchanged firmware in the emulator.
- The CPU load of 5 EQ stages. Refer to [re/custom-eq.md](../re/custom-eq.md#open-questions).
- Shuffle: does the firmware remove the tracks with "skip when shuffling" (mhit byte 0xa5)? Does Repeat All shuffle again at the end of the list? On the real iPod, one album with Album Mix and Repeat All plays with no end, and the songs stay shuffled. A new order at each pass is not known yet. Refer to [re/shuffle.md](../re/shuffle.md#open-questions).
