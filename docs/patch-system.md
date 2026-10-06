# The patch system

This document tells how iPodFirm changes the program code of RetailOS. A patch is C code that iPodFirm compiles, links at a fixed address in osos, and connects to the firmware with hooks. The code is in [Patcher.swift](../mac/Sources/IPodFWKit/Patcher.swift). [src/ipodfw/patcher.py](../src/ipodfw/patcher.py) has the same logic in Python.

## The parts of a patch

A patch is a folder in [patches/](../patches/). It holds two files:

- `patch.json`: the manifest.
- One C file. iPodFirm refuses a folder with zero or more than one C file.

`mac/scripts/build-app.sh` copies each patch folder into `iPodFirm.app/Contents/Resources/patches/`. It does not copy `row-marker`, because that patch is only for tests.

## The patch.json format

| Key | Type | Content |
|---|---|---|
| `name` | string | The name. The app shows it in the Patches pane. |
| `description` | string | The text in the Patches pane. |
| `osos_sha256` | string | The SHA-256 of the unchanged Apple osos image. For firmware 1.3 it is `784ae3d5540fd2f89e8c947b93629e97f62a06dc311d9745aab143e4db6bb251`. |
| `load_address` | hex string | The osos offset where the code goes. |
| `symbols` | object | Firmware addresses for the external functions and data that the C code uses. Name → hex address. |
| `hooks` | array | The changes to the firmware. See [The hooks](#the-hooks). |
| `hdd_warning` | string, optional | A warning. The app shows it if the iPod probably has the original hard drive. |
| `internal` | bool, optional | `true`: the patch is a part of a build step. The Patches pane does not show it. Only `dark-mode` uses this key. |

Example (from [patches/flash-keep-awake/patch.json](../patches/flash-keep-awake/patch.json)):

```json
{
  "name": "flash-keep-awake",
  "osos_sha256": "784ae3d5540fd2f89e8c947b93629e97f62a06dc311d9745aab143e4db6bb251",
  "load_address": "0x736700",
  "symbols": { "fw_resume_tail": "0x1b9118", "ka_always_on": "0x94e6c", "ka_timed": "0x94d80",
               "ka_active": "0x1086bedc", "ka_time": "0x1086bf0c" },
  "hooks": [
    { "kind": "bl", "at": "0x284c7c", "expect": "0xe5941018", "to": "hook_keep_awake_time" },
    { "kind": "bl", "at": "0xb45f4",  "expect": "0xeb0412c7", "to": "hook_after_wake" },
    { "kind": "bl", "at": "0x1d871c", "expect": "0xebfaf172", "to": "hook_storage_in_use" }
  ]
}
```

## The compiler

iPodFirm runs `/usr/bin/xcrun clang` with these flags:

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
2. The code ends after `maxSize`. The default is 0x736800, the start of rsrc in Apple's layout. The Dark Mode build uses 0x7F0000.
3. The code area is not all zero. Two patches possibly use the same area.
4. A hook word does not have its `expect` value. Another change or another firmware version is in that location.
5. The `kind` is not known, or the `to` function is not a global function of the patch.

After the checks, iPodFirm writes the code and the hooks. It extends osos with zeros to a multiple of 0x800 bytes. The partition code then calculates the new length and checksum.

## The free space

Apple's code ends at 0x7358c0. The patches use the area to 0x736800 (3904 bytes). Each patch has a fixed load address, so each patch has a fixed part of this area.

| Patch | Load address | Space | Notes |
|---|---|---|---|
| `album-art` | 0x735900 | 0x735900–0x736600 (3328 bytes) | Code, constants and variables. |
| `sleep-now` | 0x736600 | 0x736600–0x736700 (256 bytes) | |
| `flash-keep-awake` | 0x736700 | 0x736700–0x736800 (256 bytes) | |
| `row-marker` | 0x735900 | The same area as `album-art`. | Test patch. You cannot use it with `album-art`. |
| `dark-mode` | Set by the build | After the theme data, below 0x7F0000 | The value 0x7eb000 in `patch.json` is not used. |

The variables of a patch are in its area. The firmware loads osos into RAM, so the variables can change. Apple's code does not use this RAM.

## Write a new patch

CAUTION: A patch can stop the iPod at start. Test each patch in the emulator before you flash it to an iPod.

1. Find the function to change in Ghidra. Refer to [firmware-functions.md](firmware-functions.md).
2. Find a hook location: a vtable slot, or one instruction that you can replace.
3. Write down the current 32-bit value at the hook location. This is the `expect` value.
4. Select a load address in free space. Do not use the area of another patch.
5. Make a folder in `patches/` with `patch.json` and one C file.
6. Declare each firmware function in C. Add its address to `symbols`.
7. Write the hook functions. Use the same arguments as the original function.
8. Build the app with `mac/scripts/build-app.sh`.
9. Turn on the patch in the Patches pane.
10. Run the firmware in the Emulator pane.
11. Add a test to [tests/test_patcher.py](../tests/test_patcher.py) for the hook encodings.

Obey these rules in the C code:

- Do not use the C library. Use the firmware functions, for example `fw_alloc` (0x25a974) and `fw_memset0` (0x07ccd0).
- Do not use a large array on the stack. The size of the task stacks is not known.
- Do not use floating point. The CPU has no FPU, and the library functions for soft floating point are not available.
- Keep the code small. The free space is 3904 bytes for all patches.
- Return quickly from a draw hook. The firmware calls it for each label in each frame.
