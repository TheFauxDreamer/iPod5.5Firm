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
| 0x1bb260 | Draw method of the list-row label class (type 0x3180). Scrolls a long title from a cached image of the text. | Emulator, Patch |
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
| 0x211a00 | Fills a rectangle. | Patch |

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

### Settings, sleep and restart

| Address | Function | Evidence |
|---|---|---|
| 0x190b00 | "Get" method of the settings object (vtable slot 0x66c94c). Operations are four-character codes: `prID`, `Str `, `Ui32`. | Static, Patch |
| 0x1919d8 | "Set" method of the settings object (vtable slot 0x66c950). | Static, Patch |
| 0xb2e74, 0x9b240 | Setter and getter of the backlight setting (settings +0xaf8). | Static |
| 0x193b90 | Copies a setting and posts event 0x60000006 when it changes. | Static |
| 0x1eb65c | Native method: writes the backlight seconds to the application object +0x444. | Static, Emulator |
| 0x1ee8b8 | Saves the settings and the database, as before a sleep. | Static, Patch |
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
| 0x094e08 | Keep-awake message type 4 ("sleep now"). Also used before a restart. | Static, Patch |
| 0x001630 | Restart: writes 4 to `DEV_RS` (0x60006004). | Static, Emulator |

### User events

| Address | Function | Evidence |
|---|---|---|
| 0x1d81cc | UI event handler. Runs in the UI task for each button and wheel event. | Emulator |
| 0x1d813c | Starts the idle timer again and turns the display on. Called at 0x1d8344 for a button event, not for the wheel events 0x10 and 0x1c. | Emulator |
| 0x1d8264 | UI event handler part: calls 0x94bbc(4) and then 0x94d80(4, 3000) while the storage is on. | Static |
| 0x1d8570 | 5000 ms timer of key 0x6e (a long push of Play). Posts screen 0x63f2. | Static |
| 0x283e10 | Backlight function. Only the sleep and wake paths call it. | Static |

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

## Object layouts

| Object | Offset | Content |
|---|---|---|
| View | +0x10 | Parent view |
| View | +0x1c | u16: the layout element ID. The data source of a list uses it to select the data. |
| View | +0x5c | Left edge |
| View | +0x74 | Graphics context |
| View | +0x78, +0x7c, +0x80 | Child list, count, array pointer |
| Graphics context | +0x2c, +0x30 | x origin, y origin |
| Rectangle | +0, +4, +8, +12 | top, left, bottom, right |
| Application object | +0x444 | Backlight time in seconds |
| Application object | +0x487 | "Sleep pending" flag |
| Application object | +0x3e4 | Power controller |
| Keep-awake message | +0x18 | Time in ms (type 2) |
| Track | +0x28, +0x2c, +0x34, +0x3c, +0x40 | Pool indexes: title, artist, album, composer, genre |
| Track | +0x30 | Index of the artist sort key (pool db + 0x10c) |
| Music database | +0xb4, +0xe0, +0x138, +0x190 | String pools: titles, artists and composers, albums, genres |

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
| 0x1083de9c | SpiderMonkey opcode table. |

The image ends at 0x7358c0. The region from 0x10800000 (8 MB) has the pool. No code refers to the area between the image end and 8 MB. The patches and the theme data use this area.

## Hardware registers

| Address | Name | Use |
|---|---|---|
| 0x60005010 | `USEC_TIMER` | Microsecond counter. `flash-wake-on-input` reads it. |
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

## Settings keys

| Key | Item |
|---|---|
| 0x60006031 | Backlight Timer command. The values are 0x6032–0x603a. |
| 0x60006088 | Clicker |
| 0x600060b7 | Sound Check |
| 0x600060e0 | Dark Mode (added by iPodFirm) |

## Open questions

- The function that gives the current time of day. A timed dark mode needs it.
- The style of the rating stars in Now Playing. The table at 0x336190 gives a style object (0x192448 + 16 × n) for each Type ID.
- Why the stock firmware defers Sleep after a computer session.
- The path of a long push of Play.
- The function of the audio route flags at 0x1081ee48 + 0 and + 1.
- The cause of the empty artwork frame in Now Playing with the unchanged firmware in the emulator.
