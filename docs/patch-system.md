# The patch system

This document tells how iPodFirm changes the program code of RetailOS. A patch is C code that iPodFirm compiles, links at a fixed address in osos, and connects to the firmware with hooks. The code is in [Patcher.swift](../mac/Sources/IPodFWKit/Patcher.swift). [src/ipodfw/patcher.py](../src/ipodfw/patcher.py) has the same logic in Python.

## The parts of a patch

A patch is a folder. It holds these files:

- `patch.json`: the manifest.
- The code: one C file, or `patch.o` (the compiled object), or both. A data patch has no code. iPodFirm refuses a folder with more than one C file.
- Optional: a readme (`.md` or `.txt`) and `.png` files.

If the folder has `patch.o`, the patcher links `patch.o` and does not compile the C file. Thus a user does not need Xcode. `Patcher.objectCode` (Swift) and `apply` (Python, `OBJECT_FILE`) obey this rule.

There are two places for patches:

- The built-in patches are in [patches/](../patches/). `mac/scripts/build-app.sh` copies each patch folder into `iPodFirm.app/Contents/Resources/patches/`. It does not copy `row-marker`, because that patch is only for tests.
- The user patches are in `~/Library/Application Support/iPodFirm/Patches/`. The owner installs them in the app.

A user patch with the name of a built-in patch replaces the built-in patch only if the user patch has a higher `version`. Otherwise the app ignores the user patch (`PatchLibrary.list`). Thus a later app with a higher built-in version uses its built-in patch again.

### The .ipodpatch file

A `.ipodpatch` file is a zip of one patch folder (`ditto -c -k --keepParent`). macOS opens it with iPodFirm (the type `com.thefauxdreamer.ipodfirm.patch` in `Info.plist`).

To install a patch, do one of these steps:

- Double-click the `.ipodpatch` file.
- Drag the `.ipodpatch` file or the patch folder onto the list of patches.
- Click **+** below the list, or select File > Install Patch….

iPodFirm examines the patch (`PatchLibrary.inspect` in [PatchLibrary.swift](../mac/Sources/IPodFWKit/PatchLibrary.swift)) and shows the install sheet. It unzips a `.ipodpatch` file into `Staging/patch-<UUID>/` and deletes that folder after the install.

The install stops if one of these errors occurs:

- `patch.json` does not decode, or the `name` has a character that is not a–z, 0–9 or "-".
- A target has an `osos_sha256` that is not the `osos_sha256` of the patch.
- A built-in patch has the same name, and the file does not have a higher `version` than the built-in patch.
- The `version` is not one to three numbers with dots.
- The folder has a subfolder, more than one C file, or a file type that is not `.c`, `.o`, `.json`, `.md`, `.txt` or `.png`.
- `patch.o` is not an ELF32 ARM object.
- The patch has only a C file, and the Mac has no clang (`xcrun --find clang`).
- The patch has code but no `load_address`.
- A trial link fails, for example for an undefined symbol.
- A path in `ui` is not below `iPod_Control/`, or a write is larger than 1 MB.

The install continues with a note in these conditions:

- The patch is not for the Apple firmware 1.3.
- The patch has no `version_letter`, or another patch uses the letter. iPodFirm writes the first free letter into the installed `patch.json`.
- The patch has no `version`.
- The file has an older version than the installed patch (a downgrade).
- The file replaces a built-in patch.
- The patch has no `title`, `symbol` or `category`.
- The patch changes the same place as another patch (`Patcher.conflicts`).
- `ui` names a tool that the app does not have.

### Versions and updates

The install sheet compares the `version` of the file with the installed patch of the same name (`PatchCandidate.change`). It shows the two versions, for example "1.0 → 1.1". The button shows the result:

| Button | Condition |
|---|---|
| **Install** | No patch has this name. |
| **Update** | The file has a higher version. |
| **Reinstall** | The two versions are equal. |
| **Downgrade** | The file has a lower version. The sheet shows a caution. |
| **Replace Built-In Patch** | The file has a higher version than a built-in patch. The sheet shows a caution, and a second dialog asks the owner to confirm. |

A patch with no `version` is lower than all versions. The comparison uses numbers, thus "1.10" is higher than "1.9" (`PatchVersion`).

The install moves the old folder to the Trash. The patch keeps its switch state, because the app records the switched-on patches by name. If the patch is switched on, an alert tells the owner to flash the iPod again.

**−** below the list moves a user patch to the Trash. If the user patch replaced a built-in patch, the built-in patch comes back. Built-in patches cannot be removed.

### Make and share a patch

1. Write the patch as in [Write a new patch](#write-a-new-patch). Use `"load_address": "extended"`, so that the patch does not use the area of another patch.
2. Add `title`, `summary`, `symbol` and `category`.
3. Add `details`. Add `requires`, `notes` and `caution` if necessary. Do not put all the text in `description`.
4. In the Patches pane, select the patch. Click **⋯** > Export Patch…. iPodFirm compiles `patch.o` and writes the `.ipodpatch` file. The C file stays in the file as the source.
5. Give the `.ipodpatch` file to other people.

## The patch.json format

| Key | Type | Content |
|---|---|---|
| `name` | string | The name. The app shows it in the Patches pane. |
| `description` | string | One or two short sentences at the top of the section "What It Does" in the Patches pane. |
| `osos_sha256` | string | The SHA-256 of the unchanged Apple osos image. For firmware 1.3 it is `784ae3d5540fd2f89e8c947b93629e97f62a06dc311d9745aab143e4db6bb251`. |
| `targets` | array | The firmware builds that the patch is for. Each item has `model`, `firmware` and `osos_sha256`, for example `{ "model": "iPod Video (5G/5.5G)", "firmware": "1.3", "osos_sha256": "784ae3d5…" }`. The app shows `model` and `firmware` in the Compatibility section and in the install sheet. The `osos_sha256` of each item must be the same as the `osos_sha256` of the patch. The installer refuses a different value. Without `targets`, the app uses its list of known builds (`PatchSpec.knownFirmware`). |
| `load_address` | hex string | The osos offset where the code goes. |
| `symbols` | object | Firmware addresses for the external functions and data that the C code uses. Name → hex address. |
| `hooks` | array | The changes to the firmware. See [The hooks](#the-hooks). |
| `hdd_warning` | string, optional | A warning. The app shows it if the iPod probably has the original hard drive. |
| `version` | string | The version of the patch: one to three numbers with dots, for example `1.2`. Each patch that is not `internal` must have a version. Increase it at each change, so that the install sheet shows an update. The test `testPatchVersions` makes sure of this. |
| `version_letter` | string | One letter a–z. Each patch must have a letter, but an `internal` patch has no letter. If the owner switches on "Add a letter for each switched-on patch", the About screen shows this letter after the version. Each patch has a different letter. |
| `internal` | bool, optional | `true`: the patch is a part of a build step. The Patches pane does not show it. Only `dark-mode` uses this key. |
| `title` | string | The name in the Patches pane, in title case, for example "Album Artwork". If it is missing, the pane shows `name`. |
| `summary` | string | One line below the title in the list of patches. |
| `details` | array of strings, optional | The changes that the owner sees on the iPod. The section "What It Does" shows each item as a bullet below `description`. Write one short sentence for each item. |
| `requires` | array of strings, optional | The hardware or the files that the patch needs. The section "You Need" shows each item. |
| `notes` | array of strings, optional | More information. The section "Good to Know" shows each item. |
| `caution` | string, optional | A caution. The pane shows it in orange above the switch of the patch. The install sheet also shows it. |
| `symbol` | string | The name of an SF Symbol, for example `photo.on.rectangle.angled`. Do not use emoji. |
| `category` | string | The group in the list of patches: `display`, `power` or `test`. |

| `ui` | object, optional | Controls in the Patches pane. Refer to [The ui object](#the-ui-object). |

Each built-in patch that is not `internal` must have `title`, `summary`, `symbol`, `category` and `targets`. The test `testPatchMetadata` makes sure of this. It also makes sure that macOS has the SF Symbol, that each tool exists and that each `ui` path is permitted.

### The ui object

The `ui` object gives a patch controls in the Patches pane with no change to the Swift code (`PatchControls` in [PatchTools.swift](../mac/Sources/iPodFirm/PatchTools.swift)).

| Key | Content |
|---|---|
| `actions` | Buttons in the section "On the iPod". Each action has `title`, `write` and an optional `status`. Each item of `write` has `path`, and `text` or `zeros` (a number of zero bytes). |
| `toggles` | Switches. Each switch has `title`, `path`, `on` and `off`. The switch reads the file on the iPod and writes `on` or `off`. |
| `steps_title`, `steps` | A numbered list in a disclosure group. The default title is "Procedure". |
| `readme` | The name of a Markdown file in the patch folder. The pane shows it in the section "Read Me". |
| `tools` | Built-in Swift tools, by id: `album-thumbnails` (the thumbnails and the playlist artwork) and `usb-log` (the USB log). `PatchSpec.knownTools` lists them. |

Each `path` must start with `iPod_Control/` and must not contain `..`. A write can have a maximum of 1 MB (`PatchUI.maxWrite`).

Example (a part of [patches/usb-host-probe/patch.json](../patches/usb-host-probe/patch.json)):

```json
"ui": {
  "actions": [{
    "title": "Start the Probe at the Next Restart",
    "write": [
      { "path": "iPod_Control/iTunes/iPodFirmUSBLog", "zeros": 32768 },
      { "path": "iPod_Control/iTunes/iPodFirmUSBProbe", "text": "1" }
    ],
    "status": "The probe starts at the first button press after the next restart of the iPod."
  }],
  "steps_title": "Test Procedure",
  "steps": ["Flash a firmware with this patch.", "…"],
  "tools": ["usb-log"]
}
```

Example (a part of [patches/flash-keep-awake/patch.json](../patches/flash-keep-awake/patch.json)):

```json
{
  "name": "flash-keep-awake",
  "osos_sha256": "784ae3d5540fd2f89e8c947b93629e97f62a06dc311d9745aab143e4db6bb251",
  "load_address": "0x736644",
  "symbols": { "fw_resume_tail": "0x1b9118", "ka_always_on": "0x94e6c", "ka_timed": "0x94d80",
               "ka_active": "0x1086bedc", "ka_time": "0x1086bf0c",
               "fw_drive_power": "0x265cc8", "fw_task_sleep": "0x11c9fc" },
  "hooks": [
    { "kind": "bl", "at": "0x284c7c", "expect": "0xe5941018", "to": "hook_keep_awake_time" },
    { "kind": "bl", "at": "0xb45f4",  "expect": "0xeb0412c7", "to": "hook_after_wake" },
    { "kind": "bl", "at": "0x1d871c", "expect": "0xebfaf172", "to": "hook_storage_in_use" },
    { "kind": "bl", "at": "0x23344c", "expect": "0xeb00ca1d", "to": "hook_drive_power_off" }
  ]
}
```

## The compiler

If the patch folder has `patch.o`, iPodFirm does not compile. Otherwise iPodFirm runs `/usr/bin/xcrun clang` with these flags:

```
--target=armv4t-none-eabi -mcpu=arm7tdmi -marm -mfloat-abi=soft -O2
-ffreestanding -fno-builtin -fno-pic -fno-exceptions -fno-unwind-tables
-fno-asynchronous-unwind-tables -fno-stack-protector -ffunction-sections
-fdata-sections -nostdlib -Wall -Werror -c
```

The CPU of the PP5022 is an ARM7TDMI (ARMv4T). The patch code uses the ARM state. It has no C library, so it uses firmware functions for memory, strings and files. A warning stops the build (`-Werror`). Xcode or the Xcode command line tools must be installed.

## The linker

iPodFirm has its own small ELF linker (`Patcher.link`). It does these steps:

1. It reads the ELF32 object.
2. It puts each section that has `SHF_ALLOC` and the type `PROGBITS` or `NOBITS` at the load address. Each section is aligned to its own alignment, with a minimum of 4. `NOBITS` sections (`.bss`) become zeros.
3. It resolves each undefined symbol from `symbols` in `patch.json`. A build step can add more symbols, for example `dark_table`.
4. It applies the relocations in the table below.
5. It returns the code bytes and the addresses of the global symbols.

| Relocation | Number | Calculation |
|---|---|---|
| `R_ARM_ABS32` | 2 | S + A |
| `R_ARM_REL32` | 3 | S + A − P |
| `R_ARM_CALL`, `R_ARM_JUMP24` | 28, 29 | 24-bit branch offset. The target must be within ±32 MB. |
| `R_ARM_NONE`, `R_ARM_V4BX` | 0, 40 | Ignored. |

Any other relocation type stops the build. An undefined symbol that is not in `symbols` also stops the build. The error tells you to add it to `patch.json`.

## The hooks

A hook changes one 32-bit word in osos. Each hook has four keys:

| Key | Content |
|---|---|
| `kind` | `word`, `b` or `bl`. |
| `at` | The osos offset of the word. |
| `expect` | The value that the word must have in the Apple firmware. |
| `to` | A global function of the patch, or a hex address. |

| Kind | New value | Use |
|---|---|---|
| `word` | The address of `to`. | Replaces a method address in a vtable. The firmware then calls the patch for all objects of that class. |
| `bl` | `0xEB000000 \| ((to − (at + 8)) >> 2 & 0xFFFFFF)` | Replaces one instruction with a call. The patch returns to the next instruction. |
| `b` | `0xEA000000 \| ((to − (at + 8)) >> 2 & 0xFFFFFF)` | Replaces one instruction with a jump. The patch must run the replaced instruction itself and jump back. |

A `bl` hook changes `lr`. If the replaced instruction was not a call, the hook function must keep all the registers that the firmware uses after the hook. `hook_keep_awake_time` in [keep_awake.c](../patches/flash-keep-awake/keep_awake.c) is an example. It is a `naked` function that changes only `r1` and `ip`.

A `b` hook on the first instruction of a function is a wrapper. `lookup_original` in [dark_mode.c](../patches/dark-mode/dark_mode.c) runs the replaced `push {r3, r4, r5, r6, r7, lr}` and then jumps to the second instruction (`lookup_continue`, 0x21f258).

## The checks before a patch is applied

`Patcher.apply` stops with an error if one of these conditions is true:

1. The SHA-256 of the original osos is not `osos_sha256`. iPodFirm uses the hash of the osos as it was first opened. Thus picture and text edits do not stop a patch.
2. The code ends after `maxSize`. The default is 0x736800, the start of rsrc in Apple's layout. The Dark Mode build and an extended patch use 0x7F0000 (`ThemeImport.ososLimit`).
3. The code area is not all zero. Two patches possibly use the same area.
4. A hook word does not have its `expect` value. Another change or another firmware version is in that location.
5. The `kind` is not known, or the `to` function is not a global function of the patch.

After the checks, iPodFirm writes the code and the hooks. It extends osos with zeros to a multiple of 0x800 bytes. The partition code then calculates the new length and checksum.

## The free space

Apple's code ends at 0x7358c0. The bytes `55 AA 55 AA` at 0x7358c0 are a marker. Do not put code on them. The patches use the area from 0x7358d0 to 0x736800 (3888 bytes). Each patch has a fixed load address, so each patch has a fixed part of this area. After `flash-wake-on-input`, 124 bytes are free (0x736784–0x736800). A larger patch uses the extended area (see below).

| Patch | Load address | Space | Notes |
|---|---|---|---|
| `album-art` | 0x7358d0 | 0x7358d0–0x73658c (3260 bytes) | Code, constants and variables use 3080 bytes. |
| `sleep-now` | 0x73658c | 0x73658c–0x736644 (184 bytes) | The code uses 181 bytes. |
| `flash-keep-awake` | 0x736644 | 0x736644–0x736700 (188 bytes) | The functions use `__attribute__((minsize))` to make the code smaller. |
| `flash-wake-on-input` | 0x736700 | 0x736700–0x736784 (132 bytes) | Code and two variables. |
| `row-marker` | 0x7358d0 | The same area as `album-art`. | Test patch. You cannot use it with `album-art`. |
| `dark-mode` | Set by the build | After the theme data, below 0x7F0000 | The value 0x7eb000 in `patch.json` is not used. |
| `usb-host-probe` | `extended` | After all other data (8740 bytes; the 32 KB log buffer comes from the allocator) | Extended patch. Test patch. |
| `cover-flow` | `extended` | After all other data (10676 bytes; approximately 600 KB for the screen copy, the covers and the read buffer come from the allocator while Cover Flow shows) | Extended patch. |

The variables of a patch are in its area. The firmware loads osos into RAM, so the variables can change. Apple's code does not use this RAM.

### The extended area

A patch that is too large for the area before 0x736800 uses `"load_address": "extended"`. The build then puts the patch after all the data that is already in the image: the end of osos, at least 0x736800, aligned to 16 bytes (`Patcher.extendedBase`, Python `extended_base`). Thus the patch goes after a theme, the Dark Mode switch table, the Settings menu, the dark-mode code and the extended patches before it. The limit is 0x7F0000 (`ThemeImport.ososLimit`), because the reset code of RetailOS stops if the image end is after 8 MB (0x800004). The osos image gets larger than 0x736800, thus the build moves rsrc (`FirmwarePartition.makeRoom`), as for a theme.

The address of an extended patch changes with the theme and the other patches. Thus an extended patch must not use a fixed address of its own code or data in another patch.

A first version (6 October 2026) reserved the fixed area 0x7E8000–0x7F0000. It failed with the "Switch on iPod" build of a large theme: the switch table of "Dark Gray" ends at approximately 0x7ea700, thus the dark-mode code went into the reserved area.

## Write a new patch

CAUTION: A patch can stop the iPod at start. Test each patch in the emulator before you flash it to an iPod.

1. Find the function to change in Ghidra. Refer to [firmware-functions.md](firmware-functions.md).
2. Find a hook location: a vtable slot, or one instruction that you can replace.
3. Write down the current 32-bit value at the hook location. This is the `expect` value.
4. Select a load address in free space. Do not use the area of another patch.
5. Make a folder in `patches/` with `patch.json` and one C file. Or make the folder anywhere and install it in the app (drag it onto the list of patches).
6. Declare each firmware function in C. Add its address to `symbols`.
7. Write the hook functions. Use the same arguments as the original function.
8. Build the app with `mac/scripts/build-app.sh`.
9. Turn on the patch in the Patches pane. The app does not let you turn on two patches that change the same place.
10. Run the firmware in the Emulator pane.
11. Add a test to [tests/test_patcher.py](../tests/test_patcher.py) for the hook encodings.

Obey these rules in the C code:

- Do not use the C library. Use the firmware functions, for example `fw_alloc` (0x25a974) and `fw_memset0` (0x07ccd0).
- Do not use a large array on the stack. The size of the task stacks is not known.
- Do not use floating point. The CPU has no FPU, and the library functions for soft floating point are not available.
- Keep the code small. The free space is 3888 bytes for all patches.
- Return quickly from a draw hook. The firmware calls it for each label in each frame.
