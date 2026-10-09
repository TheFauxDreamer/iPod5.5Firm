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
| [CallerTree.java](../re/ghidra-scripts/CallerTree.java) | `re/ghidra-scripts/` | Writes the caller tree of functions to a given depth. |
| [SetArmOptions.java](../re/ghidra-scripts/SetArmOptions.java) | `re/ghidra-scripts/` | Pre-script. Turns on "ARM Aggressive Instruction Finder" for the first analysis. |
| `FindXrefs.java`, `FindConstant.java`, `FindBytes.java`, `ListVtable.java`, `MakeSignature.java` | `re/ghidra-scripts/` | Search scripts. Refer to [ghidra-guide.md](ghidra-guide.md#2-the-scripts). |
| [find-pattern.py](../re/find-pattern.py) | `re/` | Finds a byte pattern in a raw file without Ghidra. |
| Instrumented emulator | `~/Library/Application Support/iPodFirm/emulator-src/target/release/ipod-emulator` | The emulator with the iPodFirm instrumentation patch. Refer to [re/emulator.md](../re/emulator.md). |
| `ipodfw.emucontrol` | [src/ipodfw/emucontrol.py](../src/ipodfw/emucontrol.py) | Python control of the emulator socket. |

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

### Resources and strings

| Address | Function | Evidence |
|---|---|---|
| 0x21f254 | General resource lookup (provider, type, id). All resource and string lookups pass here, also the virtual calls. The first instruction is `push {r3-r7, lr}`. | Static, Patch (`dark-mode`) |
| 0x21f3dc | Lookup of any type. Continues in 0x21f254. | Static |
| 0x21f408 | Lookup of a `BMap`. Continues in 0x21f254. | Static |
| 0x21f418 | Lookup of a `Str ` (table, id). | Static, Patch |
| 0x21f3b8 | Returns the string table. | Patch |
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
| 0x25a974 | Allocates memory from the pool object at 0x1081da00. | Patch |
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
| 0xb4a64 | Loads the music database from `iPod_Control\iTunes\iTunesDB`. Runs at the start and after each USB session. At 0xb4ad4 it adds the usage-log event 0xf ("Exit Disk Mode"). | Static, Patch (`album-art`) |
| 0xa2310 | Makes the music database object and calls 0xb4a64 (at 0xa23fc). | Static |
| 0x1edb9c | Loads the music database again (`blne 0xb4a64` at 0x1ed2d0) if the flag at +0x489 is 0. | Static |
| 0x213c5c | Adds an event to the usage log (log, event, value). | Static, Patch |
| 0x213cd4 | Gives the name of a usage-log event. 0xe is "Enter Disk Mode", 0xf is "Exit Disk Mode". | Static |

### Settings, sleep and restart

| Address | Function | Evidence |
|---|---|---|
| 0x190b00 | "Get" method of the settings object (vtable slot 0x66c94c). Operations are four-character codes: `prID`, `Str `, `Ui32`. | Static, Patch |
| 0x1919d8 | "Set" method of the settings object (vtable slot 0x66c950). | Static, Patch |
| 0xb2e74, 0x9b240 | Setter and getter of the backlight setting (settings +0xaf8). | Static |
| 0x193b90 | Copies a setting and posts event 0x60000006 when it changes. | Static |
| 0x1eb65c | Native method: writes the backlight seconds to the application object +0x444. | Static, Emulator |
| 0x1ee8b8 | Saves the settings and the database, as before a sleep. | Static, Patch |
| 0x1a0120, 0x19ff0c | 0x1a0120 returns the disk cache object. 0x19ff0c(object) writes the cache to the disk until its queue (+0x6c) is empty. The sleep code calls them at 0x1ed8cc and 0xb4430. Without it, a file write reaches the disk only after more than 10 s. | Static, Emulator, Patch |
| 0x1ee8d0 | Sleep sequence: saves, writes the cache (0x1ed828, 0x19ff0c), then calls the sleep method. Does not sleep if external power is found. | Static, Emulator |
| 0x1ecc8c | External-power test, from saved copies of the power pins (vtable offset 0xb4 → 0x9e664). | Static |
| 0x265698 | Reads the power source pins. | Static |
| 0x1d83fc | Sleep item handler: backlight off (0xb4638), start the idle timer (controller + 0x48, 500 ms). | Static, Emulator |
| 0x1e8cd4 | App command 7. Calls the Sleep item handler at 0x1e8ce8. | Static |
| 0x1d8a40 | Idle timer handler. Sleeps only if the gate 0x1d938c passes. | Static, Emulator |
| 0x1d938c, 0x1d8d9c, 0x1d8444, 0x1d8670, 0x1d8718 | The sleep gate. Refer to [re/sleep.md](../re/sleep.md). | Static, Emulator |
| 0x1d8cd0 | Timer handler. Its part at 0x1d9308 calls 0x1ee8d0 and, after the wake, 0x1d813c. | Static, Patch |
| 0x1dfdd4 | Sleep method (vtable 0x670720, offset 0x70). Calls 0xb43dc. | Static |
| 0xb43dc | Sleep function: display off (0xb7c64(0)), keep-awake message type 4, power mode 3 or 2 (0x2823bc). After the wake it ends with `bl 0x1b9118` at 0xb45f4. | Static, Emulator |
| 0x2823bc | Power-state entry (modes 1, 2, 3, 5). | Static |
| 0x1c1f5c | Returns the voice recorder object (component 0x3d00). Byte +0x66 is 1 during a recording. | Static |
| 0x151c98 | Stops a timer. | Patch |
| 0x151c24 | Sets the interval of a timer in ms (timer, ms). Stops the timer first. | Static, Patch (`cover-flow`) |
| 0x151694 | Starts a timer. Its event goes to the owner of the timer. | Static, Patch (`cover-flow`) |
| 0x13d7c8 | Initializes a timer (owner, timer, 0, 0). The browse-list constructor 0x23b97c calls it for its two timers. | Static |
| 0x23b97c | Constructor of a browse list. Makes the timer at list + 0xcc (100 ms, the key repeat) and the timer at list + 0x104 (2000 ms). | Static |
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
| 0x88ff8 | Output volume: `level × maximum / 100`, with the maximum from +0xb78. | Static |
| 0x1a3254 | iAP command handler. Case 0x24 replies 0x25 with the bit 0x1000000 if the EU limit is set. | Static |

### User events

| Address | Function | Evidence |
|---|---|---|
| 0x1d81cc | UI event handler. Runs in the UI task for each button and wheel event. | Emulator |
| 0x1d813c | Starts the idle timer again and turns the display on. Called at 0x1d8344 for a button event, not for the wheel events 0x10 and 0x1c. | Emulator |
| 0x1d8264 | UI event handler part: calls 0x94bbc(4) and then 0x94d80(4, 3000) while the storage is on. | Static |
| 0x1d8570 | 5000 ms timer of key 0x6e (a long push of Play). Posts screen 0x63f2. The handler 0x1d81cc calls it at 0x1d8260 for each event; the code after the call does not use r0. | Static, Patch (`usb-host-probe`) |
| 0x283e10 | Backlight function. Only the sleep and wake paths call it. | Static |
| 0x13d524 | Event dispatcher (event, target). Gives the event to the filter objects (slot +0x34), then to the target or to the focused object and its parents (slot +0x30), then deletes it (event slot +4). | Static, Emulator |
| 0x23b704 | Event method of the browse lists (class 0x677290 and two other classes). Handles the push (type 4) and the wheel (type 0xf). A wheel event has +0x0c = +1 or −1 for each step, and 0 at the end of a movement. In the Albums list, `view_invalidate` (0x21ac04) on the list at the end event draws the visible rows again. | Emulator, Patch (`cover-flow`) |
| 0x23a04c | Method +0x138 of a browse list: sets the selected row and posts the property event "LstS". | Static |
| 0x1d3348 | Event method of the application object (class 0x66a510). Sends events to handlers in maps, for example 0x1d81cc. | Static, Emulator |
| 0x1d8aa4 | Key actions of the UI handler (called for the types 4–7). | Static |
| 0xa69dc | The click of the lists. Reads the Clicker setting (RAM 0x1081d9c4): bit 1 speaker (piezo message), bit 2 headphones (audio click 0x1b9168). No arguments. | Static, Emulator, Patch (`cover-flow`) |
| 0x1b9168 | Plays the click on the audio path. Then, if the byte at 0x10882440 + 0x3e has bit 0, the piezo tone 0xcd430(0x55, 3000) at 0x1b91fc. | Static, Emulator |

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

Refer to [re/album-artist.md](../re/album-artist.md). "Emulator" here means a test build of the proposed `album-artist` hook. No patch in `patches/` uses these functions yet.

| Address | Function | Evidence |
|---|---|---|
| 0x0af930 | Loads iTunesDB. Calls 0xd7888 for the tracks and 0xd6de8 for the playlists. | Static |
| 0x0d7888 | Reads the tracks (mhit) and their strings (mhod). | Static, Emulator |
| 0x0d7e40 | The jump on the mhod type. The table of `b` instructions is at 0xd7e48 + 4 × type (types 0 to 31). Type 22 (Album Artist) goes to the skip code 0xd81ec. | Static, Emulator |
| 0x0d7f58 | The code for mhod type 4 (Artist). | Static, Emulator |
| 0x0d821c | The end of the mhod loop body. It examines the result in r5. | Static, Emulator |
| 0x0d6de8 | Reads the playlists. Its mhod strings are only the playlist names. | Static |
| 0x10db84 | Reads an mhod string into a string pool. Arguments: reader, 1, type, pool, slot, 1. | Static, Emulator |
| 0x0f4340 | Reads the string header and the text. Compares the type only with 2 (path). | Static |
| 0x0885ec | Stores a text in a pool (pool, text, length, slot). Writes 0 to the slot first. The same text gets the same index and 1 more reference. | Static |
| 0x0907f4 | Updates the artist data of a track. Calls 0x1114dc. | Static, Emulator |
| 0x1114dc | Makes the artist sort key of a track (pool db + 0x10c). | Static |
| 0x0dc6a8 | Skips bytes in the file. | Static |

### USB audio

Refer to [re/usb-audio.md](../re/usb-audio.md). No patch uses these functions yet.

| Address | Function |
|---|---|
| 0x24d628 | Makes the composite USB device "iPod USB Interface". |
| 0x170f2c | The USB task. |
| 0xd85d8 | Sets the device descriptor values (vendor 0x05AC, product 0x1209 for the 5.5G). |
| 0x132614 | Makes the audio streaming object (vtable 0x666958). |
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
| 0xf5c80 | Insert an interrupt queue head into the periodic schedule. **Firmware bug:** the frame list word is (r1 + 0x34) \| 2, but the callers (0x9761c in 0x974ec, 0x96d14 in 0x96c44) give the queue head only in r0. Real iPod: the frame list pointed to the controller object +0x34 (a block of zeros). Static, Real iPod. UIM controller object (`*(0x1084a778 + 0xc)`): +0x3c the processor address of the first queue head of each frame, +0x44 the frame list. A queue head keeps its controller address at +0x34 (processor address \| 0x80000000), its software next at +0x30, its interval byte at +0x3c and its offset at +0x3d. Emulator: an empty frame list holds 1 (terminate) in each frame. |
| 0xc50ac | Driver score for "add device" (device descriptor, registry entry). 1000 if the vendor ID is equal to the record +8 and the entry is not in use. 100 if the device class is equal to the record +0x35, 110 if the subclass is also equal to +0x36, and 10 more if the protocol is equal to the u16 at +0xe. 0 if the record flags +0x3c have bit 2 and nothing matches. Static. |
| 0x6bc3dc | Class driver registry (44-byte entries: record, dispatch, +0x15 in use). Entries: hub (class 9), composite (class 0, record 0x1084a308), composite (class 2, record 0x1084a360), storage (class 8), ICA camera (vendor 0x04A9), PTP camera (class 6/1/1). No entry matches class 0xEF or an audio device. Static, Real iPod. |
| 0x108b6c | Composite driver validate: `mov r0, #0; bx lr`. It accepts each device. Static. |
| 0xcba54 | Completion callback of an interrupt transfer (request, status, bytes). Called by 0xcbfb8. The hub driver gives it with the status-change interrupt transfer. |
| 0xe7a50 | hubAddDeviceHandler: a state machine (+0x18) for a new device on a hub port. The completion callback drives it. |
| 0xe7980 | Root port status (port, &{wPortStatus, wPortChange}). Called at 0xd28f0 (root hub GET_STATUS) and 0x10e75c (status-change poll 0x10e6e0). |

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

## Vtables and classes

| Address | Content |
|---|---|
| 0x66e470 | Slot of the draw method of the list-row label (0x1bb260). |
| 0x677a14 | Slot of the draw method of the general label (0x244924). |
| 0x66b4dc | Vtable of a list cell. The parent of a label in a list row has this class. |
| 0x66b298 | Vtable of a plain view. The parent of a label in Now Playing has this class. |
| 0x66d89c | Vtable of a picture view (for example the ">" arrow). |
| 0x66c8c0 | Vtable of the Settings controller. |
| 0x66c94c, 0x66c950 | Slots of the "get" and "set" methods of the settings object. |
| 0x670720 | Vtable of the power controller. +0x6c: display on/off. +0x70: sleep. +0xb4: external power. |
| 0x69fd2c | A table entry that points to the Sleep item handler 0x1d83fc. |
| 0x666920, 0x666958 | Vtables of the USB audio control and streaming objects. |
| 0x677290 | Vtable of a browse list (for example Albums and Artists). +0x30 (0x6772c0): event method 0x23b704. +0x138 (0x6773c8): set the selection. |
| 0x6701f0 | Slot of the UI event handler 0x1d81cc. |
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
| Track | +0x00, +0x04 | The database; the next track |
| Music database | +0x1c, +0x20 | Track count; the track array (0x110 bytes for each track) |
| String pool (`strc`) | +0x08, +0x10, +0x14 | Handle to the entries {offset, length}; handle to the UTF-16 text; entry count |
| Library | +0xcf0, +0xcf8 | A track list (0 while the Albums list shows); the database |
| Library | +0xc60, +0xc6c | The album list: the album pool index of each row of the Albums list (without "All"), in its order; the count |
| Library | +0xc48, +0xc50 | The artist list (artist pool), filled when the Artists list opens |
| Track list | +0x2fc + 4 × slot | Sorted array of items (the item at + 0x10 + 4 × i; item + 0x20 is the track). Slot 6: by album. |
| Main provider | +0x1c, +0xc0 … +0xdc | The library; the row counts of the browse lists |
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
| 0x1081da00 | Allocator pool object. |
| 0x1086bedc | Keep-awake slot flags (45 bytes). |
| 0x1086bf0c | Keep-awake time left in ms (45 words). 0xffffffff = always on. |
| 0x1081ff2c, 0x1081ff30, 0x1081ff34 | Power pin monitor objects (byte +6 is the saved pin state). |
| 0x108234ec | State of the USB audio streaming object. |
| 0x1081ee48 | Audio route state. |
| 0x108710dc | Device information object: +0x92 region code, +0x94 flags (bit 0 = EU volume limit). |
| 0x1083de9c | SpiderMonkey opcode table. |
| 0x10882c3c | The display server. |
| 0x1081e0d4 | The layer index of the display (0). |
| 0x1081ec54 | Byte: the damage callback binds the layer if it is not 0. |
| 0x1081da80 | Pointer to the application object (class 0x66a510). |
| 0x1081d9c4 | The Clicker setting: bit 1 speaker, bit 2 headphones. |

The image ends at 0x7358c0. The region from 0x10800000 (8 MB) has the pool. No code refers to the area between the image end and 8 MB. The patches and the theme data use this area.

## Hardware registers

| Address | Name | Use |
|---|---|---|
| 0x60005010 | `USEC_TIMER` | Microsecond counter. `flash-wake-on-input` and `something-comforting` read it. |
| 0x7000a000 | `PWM0_CTRL` | The piezo: `period \| 0x80800000` plays a tone, 0 stops it. |
| 0x60006004 | `DEV_RS` | Device reset. 4 restarts the iPod. |
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
| Str 0x7e00 | "Dark Mode" (added by the `dark-mode` patch). |
| Str 0x7e01, 0x7e02 | "Something Comforting" and "Play" (added by the `something-comforting` patch). |

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
| The Artists list (the list view itself) | 0x6387 |

## Settings keys

| Key | Item |
|---|---|
| 0x60006031 | Backlight Timer command. The values are 0x6032–0x603a. |
| 0x60006088 | Clicker |
| 0x600060b7 | Sound Check |
| 0x600060e0 | Dark Mode (added by iPodFirm) |
| 0x600060e4 | Something Comforting (added by the `something-comforting` patch). Not a 32-bit word in osos 1.3. |

## Open questions

- The function that gives the current time of day. A timed dark mode needs it.
- The style of the rating stars in Now Playing. The table at 0x336190 gives a style object (0x192448 + 16 × n) for each Type ID.
- Why the stock firmware defers Sleep after a computer session.
- The path of a long push of Play.
- The key code 0x6e: the emulator gives it for the button `menu`, but the note on 0x1d8570 says "a long push of Play". A test on the real iPod can answer which is correct.
- The function of the audio route flags at 0x1081ee48 + 0 and + 1.
- The UIM interrupt handler that completes the periodic USB host transfers.
- The cause of the empty artwork frame in Now Playing with the unchanged firmware in the emulator.
