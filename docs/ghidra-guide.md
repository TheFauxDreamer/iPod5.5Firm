# The Ghidra guide

This guide tells how to examine the iPod firmware with Ghidra. It is for people and for AI agents. It has these parts:

1. [Set up Ghidra](#1-set-up-ghidra) and import a firmware.
2. [The scripts](#2-the-scripts) of this project.
3. [Search recipes](#3-search-recipes): one procedure for each type of question.
4. [Facts about the ARM code](#4-facts-about-the-arm-code) that help you read it.
5. [The procedure for an AI agent](#5-the-procedure-for-an-ai-agent).
6. [Port a patch to another firmware version](#6-port-a-patch-to-another-firmware-version).
7. [Support another iPod model](#7-support-another-ipod-model).
8. [Record the results](#8-record-the-results).

The results of the research are in [firmware-functions.md](firmware-functions.md). Each example in this guide is a real result from firmware 1.3 for the iPod Video. The project tested each command on 6 October 2026 with Ghidra 12.1.4.

CAUTION: The firmware, the osos image and the Ghidra project contain Apple code. Do not commit them to Git. Do not publish them.

## 1. Set up Ghidra

### 1.1 Install the tools

1. Download Ghidra 12.1.4 from the Ghidra project on GitHub.
2. Download a Java 21 JDK, for example Temurin 21.
3. Put both in `~/Library/Application Support/iPodFirm/tools/`.
4. On an Apple silicon Mac, build the native decompiler. The download does not include it:

   ```sh
   cd "$HOME/Library/Application Support/iPodFirm/tools/ghidra_12.1.4_PUBLIC"
   JAVA_HOME="../jdk-21.0.12.1+1/Contents/Home" support/gradle/gradlew buildNatives
   ```

5. Copy `build/os/mac_arm_64/*` to `os/mac_arm_64/` in each module.

On the Mac of the owner, these tools are already installed. Do not install them again.

### 1.2 Get the osos image

```sh
uv run ipodfw extract iPod_25.1.3.ipsw -o fw.bin
uv run ipodfw info -r fw.bin
uv run python -c "from ipodfw.partition import FirmwarePartition as F; open('osos.bin','wb').write(F(open('fw.bin','rb').read()).image('osos'))"
```

`ipodfw info` shows the model code. 0xB0 is the iPod Video.

### 1.3 Import the image

Make a new project for each firmware version. Use these settings:

| Setting | Value | Reason |
|---|---|---|
| Loader | `BinaryLoader` (Raw Binary) | osos has no executable format. |
| Language | `ARM:LE:32:v4t` | The PortalPlayer CPUs have ARM7TDMI cores (ARMv4T). |
| Base address | `0x0` | Then a Ghidra address is equal to the osos offset and to the patch address. |
| Pre-script | `SetArmOptions.java` | Turns on "ARM Aggressive Instruction Finder". Without it, Ghidra finds less code. |

The command:

```sh
T="$HOME/Library/Application Support/iPodFirm/tools"
R="$HOME/Library/Application Support/iPodFirm/re"
JAVA_HOME="$T/jdk-21.0.12.1+1/Contents/Home" \
  "$T/ghidra_12.1.4_PUBLIC/support/analyzeHeadless" "$R/ghidra-project" osos13 \
  -import osos.bin -processor ARM:LE:32:v4t -loader BinaryLoader -loader-baseAddr 0x0 \
  -scriptPath re/ghidra-scripts -preScript SetArmOptions.java
```

Replace `osos13` with a new project name for a different firmware, for example `osos121`.

The analysis of the 7 MB image takes approximately 5.5 minutes on an Apple silicon Mac (322 seconds in the test on 6 October 2026). The log can show `ERROR Unexpected Exception (ArmAnalyzer) ... ContextChangeException`. This error does not stop the analysis. Make sure that the log ends with `Import succeeded`.

The project tested this command with osos 1.3 in a new project. `MakeSignature.java` gave the same signature as in the project `osos13`. Thus two analyses of the same image give the same result for the scripts.

### 1.4 Run a script

A script runs on the saved project. It does not change the project when you use `-readOnly`. Use this shell function:

```sh
ghidra() {
  local T="$HOME/Library/Application Support/iPodFirm/tools"
  local R="$HOME/Library/Application Support/iPodFirm/re"
  JAVA_HOME="$T/jdk-21.0.12.1+1/Contents/Home" \
    "$T/ghidra_12.1.4_PUBLIC/support/analyzeHeadless" "$R/ghidra-project" osos13 \
    -process osos-1.3.bin -noanalysis -readOnly -scriptPath re/ghidra-scripts "$@"
}
```

Example:

```sh
ghidra -postScript FindXrefs.java /tmp/xrefs.tsv 0x94cec
```

One run takes approximately 10 seconds. You can put many `-postScript` items in one run. This is faster than one run for each script:

```sh
ghidra -postScript FindXrefs.java /tmp/a.tsv 0x265cc8 \
       -postScript DecompileAt.java /tmp/b.c 0x94cec
```

In zsh, a variable with spaces does not split into words. Use an array for a list of addresses.

## 2. The scripts

The scripts are in [re/ghidra-scripts/](../re/ghidra-scripts/). The first argument of each script is the output file. Addresses are hexadecimal, with or without `0x`. The output is text with tab characters, so that a person, a shell command or an AI can read it.

| Script | Arguments | Output | Question that it answers |
|---|---|---|---|
| `DecompileAt.java` | OUT ADDRESS... | C code, callers, callees | What does this function do? |
| `CallerTree.java` | OUT DEPTH ADDRESS... | depth, entry, body, name, call site | Which paths lead to this function? |
| `FindXrefs.java` | OUT ADDRESS... | target, from, type, function, instruction | Which code or data refers to this address? |
| `FindConstant.java` | OUT [--half] VALUE... | value, kind, address, function, instruction | Where does the program use this number? |
| `FindBytes.java` | OUT PATTERN... | pattern, address, function, instruction | Where are these bytes? |
| `ListVtable.java` | OUT ADDRESS [COUNT] | slot, offset, value, kind, function | Which methods does this class have? |
| `MakeSignature.java` | OUT ADDRESS [BEFORE] [AFTER] | pattern, offset, matches, fixed | How do I find this code in another version? |
| `SetArmOptions.java` | — | — | Pre-script for the import. |

[re/find-pattern.py](../re/find-pattern.py) finds a pattern in a raw file without Ghidra. It uses the same pattern format as `FindBytes.java`.

### Pattern format

- Bytes in memory order, in hexadecimal: `18 10 94 e5`. Spaces are optional.
- `??` is any byte.
- `text:ABC` is ASCII text. Use `_` for a space.

CAUTION: The firmware is little-endian. The instruction word 0xe5941018 is the bytes `18 10 94 e5` in memory. Do not write the word as `e5 94 10 18`.

## 3. Search recipes

Each recipe gives a question, the steps and a real example.

### 3.1 Who calls this function?

1. Run `FindXrefs.java` with the function entry.
2. For a longer path, run `CallerTree.java` with a depth of 2 or 3.

Example: the callers of the drive power function 0x265cc8.

```text
# target  from      type                function             instruction
00265cc8  00233710  UNCONDITIONAL_CALL  FUN_002336dc@002336dc bl 0x00265cc8
00265cc8  0028249c  UNCONDITIONAL_CALL  FUN_002823bc@002823bc bl 0x00265cc8
00265cc8  0071720c  COMPUTED_JUMP       thunk_FUN_00265cc8@0071720c ldr pc,[0x717210]
00265cc8  0023344c  UNCONDITIONAL_CALL  FUN_00233358@00233358 bl 0x00265cc8
```

The call at 0x23344c is the hook site of `flash-keep-awake` hook 5. A `thunk` is a short function that jumps to the real function.

Example: `CallerTree.java OUT 2 0x94cec` gives this path:

```text
0  00094cec  ...  FUN_00094cec  -
1  001d8718  ...  FUN_001d8718  001d871c
2  001d8444  ...  FUN_001d8444  001d845c
```

This is the sleep gate. Each line gives the call site in the last column.

CAUTION: Ghidra does not find a call through a vtable or a function pointer. If `FindXrefs` finds no caller, the function is possibly a method. Use [3.3](#33-which-vtable-slot-has-this-method).

### 3.2 What does this function do?

1. Run `DecompileAt.java` with an address in the function.
2. Read the callers and the callees in the first lines.
3. Read the C code. Give names to the parameters in your notes, not in the project.

Example: `DecompileAt.java OUT 0x94cec`:

```c
undefined4 FUN_00094cec(void)
{
  int iVar1;
  iVar1 = 0;
  do {
    if (*(char *)(DAT_00094d18 + iVar1) != '\0') {
      return 1;
    }
    iVar1 = iVar1 + 1;
  } while (iVar1 < 0x2d);
  return 0;
}
```

The function examines 0x2d (45) flags and returns 1 if one flag is set. These are the 45 keep-awake slots. `DAT_00094d18` is a literal pool word. It holds the address of the flags (0x1086bedc).

If no function contains the address, `DecompileAt.java` makes a function at the nearest `push {..., lr}` before the address.

### 3.3 Which vtable slot has this method?

1. Run `FindConstant.java` with the method address.
2. Look for the kind `word`. A word in a table that holds the method address is a vtable slot.

Example: `FindConstant.java OUT 0x244924`:

```text
0x244924  word  00677a14  -  -
```

0x677a14 is the slot that the `album-art` patch replaces.

### 3.4 Which methods does this class have?

1. Run `ListVtable.java` with the vtable address and a count.
2. Read the kind of each slot: `function`, `code`, `data`, `zero` or `other`.
3. Read the references to the table at the end. The function that writes the table address into an object is usually the constructor.

Example: `ListVtable.java OUT 0x670720 50` (the power controller):

```text
00670720  0x0   0x00000000  zero      -
0067078c  0x6c  0x001dfef0  code      -
00670790  0x70  0x001dfdd4  function  FUN_001dfdd4
# references to the table:
#   001e0818  DATA  FUN_0018ad44@0018ad44
```

Slot +0x70 is the sleep method. `FUN_0018ad44` refers to the table, so it is probably the constructor.

The kind `code` means that the analysis found instructions there, but no function. The slot is still a method. Use `DecompileAt.java` on it.

The start of a vtable is not marked. A table ends where the words are no longer addresses in the program. The script stops after 4 such words.

### 3.5 Where does the program use this number?

Use this recipe for a resource ID, a string ID, an element ID, a settings key, a hardware register or a size.

1. Run `FindConstant.java` with the value.
2. For a 16-bit ID in a data structure, add `--half`.
3. Read the kind:
   - `immediate`: an instruction has the value. Example: `mov r1, #0x30`.
   - `literal`: an instruction loads the value from a literal pool.
   - `word`: a 32-bit word in memory has the value. Look for the code that loads this word.
   - `half`: a 16-bit value in memory.

Example: `FindConstant.java OUT 0x6421` (the element ID of the album name):

```text
0x6421  literal  001e868c  FUN_001e804c@001e804c  ldrne r2,[0x1e8938]
0x6421  word     001e8938  -  -
0x6421  word     004f1730  -  -
```

The code at 0x1e868c loads the ID. The words at 0x4f1730 and later are in data tables.

Example: `FindConstant.java OUT --half -140` (the string "2 Seconds"):

```text
-140  half  004b06e0  -  -
-140  half  004b06e8  -  -
```

These are the string IDs in the Backlight Timer menu. The `backlight-60s` patch changes them. With `--half`, a small value gives many results (72 for −140). Look for clusters at known resource addresses.

Example: hardware registers `FindConstant.java OUT 0x70000080 0x60005010 0x6000d13c`:

```text
0x60005010  literal  000ded0c  FUN_000ded04@000ded04  ldr r6,[0xdee7c]
0x70000080  literal  001c7f8c  FUN_001c7f58@001c7f58  ldreq r0,[0x1c7fa4]
```

The register 0x6000d13c (GPIOL) gave only `word` results and no `literal`. Ghidra did not connect each literal pool word to the instruction that loads it. For a `word` result in the code area, find the load:

1. Note the address of the word, for example `W`.
2. Run `FindXrefs.java` with `W`.
3. If there is no reference, decompile the function before `W`. A literal pool is usually directly after the function that uses it.

CAUTION: ARM code cannot put most 16-bit or 32-bit values in one instruction. The compiler can also make a value with two instructions, for example `mov r0, #0x6400` and then `add r0, r0, #0x21`. `FindConstant.java` does not find this form. If you find nothing, search for the parts.

### 3.6 Where are these bytes or this text?

1. Run `FindBytes.java` with a pattern, or `re/find-pattern.py` on the raw file.
2. Read the count of matches on the last line.

Example: `text:portalplayer` gives 1 match at 0x20, the banner in the vector table.

Most of the text of the user interface is not C text. It is in the `Str` resources, and the code refers to it by a string ID. Thus:

1. Find the string with `uv run ipodfw unpack` (the JSON files in `strings/`).
2. Search for its ID with [3.5](#35-where-does-the-program-use-this-number).

### 3.7 Which code runs for this action?

Static search cannot always find the code for a user action. Use the emulator. [re/emulator.md](../re/emulator.md) describes the instruments.

1. Start the instrumented emulator with `IPODFW_PROFILE=1`.
2. Go to the screen. Wait. Record the histogram (`hist`) without the action.
3. Do the action. Record the histogram again.
4. Compare the two histograms. The 64-byte blocks that run only with the action belong to it.
5. Decompile the functions of these blocks.
6. To find the arguments, set `IPODFW_REGS_AT=ADDRESS,COUNT` and use `regs`.
7. To find the sequence and the time of calls, set `IPODFW_MARK_AT=ADDR,ADDR,...` and use `evlog`.

Example from this project: one scroll of the Albums list ran 515 blocks of general list code and 53 blocks only for the Albums list. The 53 blocks led to the text functions near 0x223000 and to the JavaScript interpreter 0x135b2c.

### 3.8 Is the behaviour in a script?

Some behaviour is not in ARM code. The compiled JavaScript in `TCmd` 9088 (osos 0x4b441c, 91,662 bytes) controls it. Signs:

- The ARM code for the action is very short.
- The emulator records the interpreter 0x135b2c during the action. Record r0 at 0x135b84 to get the bytecode address.
- `FindConstant.java` finds a value only in the `TCmd` area.

Example: the backlight times are in a switch at 0x4ba9f9 in `TCmd`. Each case is `58 <value>` then `77 <offset>`. Refer to [re/backlight-timer.md](../re/backlight-timer.md).

## 4. Facts about the ARM code

| Fact | Detail |
|---|---|
| Instruction set | ARM state, 4-byte instructions. The research found no Thumb code in the hook areas. |
| Arguments | `r0`–`r3`. More arguments are on the stack. |
| Return value | `r0`. A 64-bit value is in `r0` and `r1`. A 64-bit argument starts at an even register (for example `r2:r3` in `file_seek`). |
| Saved registers | `r4`–`r11` and `sp`. A function can change `r0`–`r3`, `ip` (`r12`) and `lr`. |
| Function start | Usually `push {..., lr}` (`stmdb sp!, {...}`, word 0xe92dXXXX with bit 14 set). |
| Function end | `pop {..., pc}` or `bx lr`. |
| Call | `bl` (word 0xebXXXXXX). The 24-bit offset is `(target − (site + 8)) / 4`. |
| Jump | `b` (word 0xeaXXXXXX), or a condition code in place of `e`. |
| Literal pool | A word after the function. `ldr rX, [pc, #n]` loads it. |
| Virtual call | The decompiler shows `(**(code **)(*param_1 + 0xb4))(param_1)`. The number is the byte offset of the slot in the vtable. |
| Object | The first word is the address of the vtable. |
| Resource tags | Four characters in a register, for example `'View'` = 0x56696577. |

Because of the `bl` format, a call to a function F has a different word at each site. Thus a byte search cannot find all calls to F. Use `FindXrefs.java`.

## 5. The procedure for an AI agent

This section is for an AI agent that uses Ghidra for this project. Obey it in addition to [CLAUDE.md](../CLAUDE.md).

### 5.1 The rules

1. Do not flash an iPod. Only the owner flashes. Test each patch in the emulator first.
2. Do not write an address into a patch if you have only one source for it. Get a second source: a second static result, an emulator record, or a patch that operates in the emulator.
3. Do not guess an address, an offset or a value. Measure it with a script or with the emulator.
4. Record each result with its source. Use the labels Static, Emulator, Patch, Real iPod and External from [firmware-functions.md](firmware-functions.md#confidence).
5. Read the current results first: [firmware-functions.md](firmware-functions.md) and the notes in [re/](../re/). Do not repeat work.
6. Use `-readOnly`. Do not save changes to the shared Ghidra project.
7. Do not commit an output file that contains Apple code, for example a large decompiled file. Write a summary.

### 5.2 The loop

Do these steps for each question:

1. Write the question in one sentence. Example: "Which function turns off the drive power?"
2. Write what you already know: addresses, IDs, strings, hardware registers.
3. Select a recipe from [section 3](#3-search-recipes).
4. Run the script. Put several scripts in one run if they do not depend on each other.
5. Read the output. Write a hypothesis with an address.
6. Get a second source for the hypothesis:
   - a caller or a callee that agrees;
   - an emulator marker at the address during the action;
   - a register record with the expected arguments.
7. If the second source does not agree, reject the hypothesis. Go back to step 3.
8. Record the result (refer to [5.4](#54-the-result-record)).

### 5.3 When to stop

Stop and report to the owner if one of these conditions occurs:

- Five loops do not give a hypothesis that has a second source.
- The only possible hook site is in a function that runs at start, in an interrupt or in the storage driver. A defect there can stop the iPod at start.
- The change needs a write to the NOR flash, to `aupd` or to `hibe`.
- The change needs more space than the free area. Refer to [patch-system.md](patch-system.md#the-free-space).
- The result disagrees with a fact in [firmware-functions.md](firmware-functions.md).

In the report, give the question, the steps, the evidence and the open points.

### 5.4 The result record

Write each result in the note in `re/` for the topic. Use this format:

```markdown
| Address | Function | Evidence |
|---|---|---|
| 0x94cec | Returns 1 if any of the 45 keep-awake slots is active. | Static (DecompileAt), Emulator (IPODFW_MARK_AT, 60 wheel steps, 0 calls) |
```

Then copy the result into the table of its area in [firmware-functions.md](firmware-functions.md).

### 5.5 From a result to a patch

1. Select the hook kind. Refer to [patch-system.md](patch-system.md#the-hooks):
   - a vtable slot (`word`) to replace a method for all objects of a class;
   - a `bl` site to replace one call;
   - the first instruction (`b`) to wrap a function.
2. Read the word at the hook site. This is the `expect` value.
3. For a `bl` hook on an instruction that is not a call, find the registers that the code uses after the site. The hook must keep them.
4. Write the patch. Follow [patch-system.md](patch-system.md#write-a-new-patch).
5. Test in the emulator. Use `IPODFW_MARK_AT` with the hook address to prove that the hook runs.
6. Update the documents. Refer to [Keep the reference current](README.md#keep-the-reference-current).

## 6. Port a patch to another firmware version

Each patch has fixed addresses for one osos (`osos_sha256`). This section tells how to find the same addresses in a different version, for example 1.2.1.

CAUTION: The project did not test a port. The procedure below uses scripts that the project tested on 1.3. Test each ported patch in the emulator before a flash.

### 6.1 What a port must find

| Item | Example | Method |
|---|---|---|
| A `bl` or `b` hook site | 0x284c7c | A code signature of the site |
| A vtable slot (`word` hook) | 0x677a14 | A code signature of the method, then `FindConstant` |
| A firmware function in `symbols` | `fw_alloc` 0x25a974 | A code signature of the function entry |
| A RAM address in `symbols` | `ka_active` 0x1086bedc | Decompile the ported function that uses it, and read its literal pool |
| A RAM address in the C code | `APP` 0x1081da18 | The same as above |
| An object offset in the C code | `VIEW_LEFT` 0x5c | Decompile the ported function, and compare it with the 1.3 function |
| A resource ID or element ID | 0x6421 | `ipodfw unpack`, or the ID map of `ThemeImport.idMap` |
| The load address | 0x7358d0 | The end of the Apple code in the new osos. In 1.3 the bytes `55 AA 55 AA` mark it. Verify the marker in the new version. |
| The hook `expect` value | 0xe5941018 | Read the word at the new site |

### 6.2 Make the signatures in the old version

For each hook site and each function in `symbols`:

1. Run `MakeSignature.java OUT ADDRESS` in the project of the old version.
2. Make sure that `matches` is 1 and that there is no `warning`.
3. If `matches` is more than 1, run it again with larger values, for example `MakeSignature.java OUT ADDRESS 10 10`.
4. For a function entry, use `MakeSignature.java OUT ADDRESS 0 12`. The function start is then the start of the pattern.
5. For a vtable slot, `MakeSignature.java` gives a warning, because each word in a vtable is an address. Make a signature of the method instead.

The script replaces the parts that change when code moves: branch offsets, `pc`-relative load offsets, and words that are addresses. The appendix has the signatures of all hook sites of firmware 1.3.

### 6.3 Find the signatures in the new version

1. Get the new osos (refer to [1.2](#12-get-the-osos-image)).
2. Run `re/find-pattern.py` on the new osos with each signature. This needs no Ghidra project.
3. For each signature with exactly 1 match, the new site is the match plus `offset`.
4. For each signature with 0 matches, the code changed. Make the signature shorter (smaller BEFORE and AFTER) and try again. Then examine the result in Ghidra.
5. For each signature with more than 1 match, examine each match in Ghidra.

### 6.4 Find the vtable slots

1. Find the method with its signature (6.3).
2. Run `FindConstant.java` with the new method address in the project of the new version.
3. The `word` result is the slot.

The project tested this method on 1.3 for the five vtable hooks:

| Method | Signature matches | Slot that `FindConstant` found |
|---|---|---|
| 0x1bb260 | 1 | 0x66e470 |
| 0x244924 | 1 | 0x677a14 |
| 0x1d83fc | 1 | 0x69fd2c |
| 0x190b00 | 1 | 0x66c94c |
| 0x1919d8 | 1 | 0x66c950 |

### 6.5 Verify each ported address

A unique signature is not proof. For each new address:

1. Decompile the old function and the new function.
2. Compare the structure: the calls, the constants and the offsets.
3. Compare the callers.
4. In the emulator, set `IPODFW_MARK_AT` at the new hook site, and do the action. The marker must show.

### 6.6 Make the ported patch

1. Copy the patch folder. Add the version to the name, for example `patches/album-art-1.2.1/`.
2. Write the new `osos_sha256`, `load_address`, `symbols` and `hooks`.
3. Change the constants in the C file if the object offsets changed.
4. Give the patch the same `version_letter` as the original only if the two can never be in one build.
5. Run the tests and the emulator.

CAUTION: iPodFirm supports one osos per patch folder. The app downloads and uses only the Apple firmware 1.3 as the target of a theme. A port to another version also needs changes to the app. Discuss them with the owner first.

## 7. Support another iPod model

### 7.1 What depends on the model

| Item | Where | Change for a new model |
|---|---|---|
| The model code 0xB0 | `FirmwarePartition.videoModelCode`, `Operations.checkModel` | Accept the new code. |
| The Apple firmware URL and SHA-256 | `IPSW.videoFirmware13`, `AppModel.appleFirmwareSHA256` | Add the firmware of the new model. |
| The partition format | `Partition.swift` | The PortalPlayer iPods use the same `]ih[` directory. Verify it. |
| The image base | `FirmwarePartition.init` | The code tries 2048, 512, 1024, 4096 and 0. Verify the result. |
| The resource formats | `Resources.swift`, `Pictures.swift` | iPodWizard supports other models. Verify the picture formats and the screen size. |
| All patch addresses | `patches/` | Find them again with [section 3](#3-search-recipes). Signatures from the iPod Video help only if the code is the same. |
| The hardware registers | The C code of the patches | The PortalPlayer CPUs of the different models have different registers for some functions. Use the Rockbox source for the model. |
| The emulator | Emulator pane | The emulator supports only the iPod Video. Without an emulator, the risk of each test is higher. |
| The size limit of osos | `ThemeImport.ososLimit`, `Patcher.maxOSOSSize` | Find the limit in the reset code of the new firmware (the iPod Video compares with 0x800004 at 0x308). |

### 7.2 The models

| Model | CPU | Difficulty | Notes |
|---|---|---|---|
| iPod Video 5G, firmware 1.2.1 or earlier | PortalPlayer, the same as 1.3 | Low | The same model code (0xB0). The work is a port (section 6). |
| iPod photo / color, iPod 4G, iPod mini, iPod nano 1G | PortalPlayer | Medium | The same partition format. Different screens, resources and registers. No emulator. |
| iPod classic 6G and later, iPod nano 3G and later | Samsung S5L87xx | Not possible with this method | The osos of the classic 6G (firmware 1.1.2) is encrypted and signed ("S5L8702 Secure Boot"). Ghidra cannot analyze the file. RepriseOS decrypts the 6.5G and 7G firmware on the iPod with a BootROM exploit, and then uses Ghidra. Refer to [re/ipod-classic-6g.md](../re/ipod-classic-6g.md). |

### 7.3 The first steps for a new model

1. Get the Apple firmware of the model. Run `uv run ipodfw info -r` on it.
2. Make sure that the directory, the checksums and the resource blocks parse.
3. Import osos into a new Ghidra project (section 1.3).
4. Find the anchors: the resource lookup (compare with 0x21f254), the file functions (compare with 0x08f38c) and the memory allocator (compare with 0x25a974). Use signatures first, then the recipes.
5. Make a small test patch for the new model, for example a patch that draws a bar at each label. It proves that the compiler, the linker and the draw functions operate. The removed patch `row-marker` is an example (refer to [modifications.md](modifications.md#row-marker-removed)).
6. Record each result in a new note in `re/`, for example `re/model-nano1g.md`.

## 8. Record the results

1. Write each experiment in a note in [re/](../re/), in the sequence of the work.
2. Copy each verified result into [firmware-functions.md](firmware-functions.md), with its evidence.
3. If a result changes a patch, update [modifications.md](modifications.md).
4. If you add or change a script, update [section 2](#2-the-scripts) of this guide.
5. Write all text in ASD-STE100 Simplified Technical English.

## Appendix: signatures of the hook sites in firmware 1.3

`MakeSignature.java` made these signatures with the default window (6 words before, 6 words after). Each has exactly 1 match in osos 1.3. The hook site is the match plus 24 bytes.

| Site | Patch | Signature |
|---|---|---|
| 0x1e8ce8 | `sleep-now` | `???????? 070051e3 0000a013 10402de9 1080bd18 e40390e5 ??????eb 0100a0e3 1080bde8 ????9fe5 100090e5 e80390e5 001090e5` |
| 0x1ee930 | `sleep-now` | `180094e5 ??????eb 0010a0e3 0300a0e3 ??????eb 0400a0e1 ??????eb 000050e3 ??????0a 0400a0e1 ??????eb 000050e3 ??????1a` |
| 0x284c7c | `flash-keep-awake` | `??????0a 0010e0e3 0060c9e7 00118ae7 1c6084e5 ??????ea 181094e5 000051e3 0080c907 002097e5 020050e1 00808705 00118ae7` |
| 0xb45f4 | `flash-keep-awake` | `??????eb ??????eb 000050e3 ??????1b ??????eb 0110a0e3 ??????eb 5cd08de2 f080bde8 0200a0e3 ??????eb 0500a0e1 ??????eb` |
| 0x1d871c | `flash-keep-awake` | `??????1a 0000a0e3 1080bde8 0100a0e3 1080bde8 10402de9 ??????eb 000050e3 0100a003 0000a013 1080bde8 1eff2fe1 10402de9` |
| 0x23344c | `flash-keep-awake` | `140094e5 050050e1 ??????1a 0400a0e1 ??????eb 0000a0e3 ??????eb 0000a0e3 7080bde8 65657266 0110a0e3 581080e5 600090e5` |
| 0x1d8344 | `flash-wake-on-input` | `0500a0e1 ??????eb 1c0050e3 ??????0a 0110a0e3 0400a0e1 ??????eb 040095e5 0f0050e3 ??????0a 0400a0e3 ??????eb 000050e3` |
| 0xafc8c | `album-artists` | `1800d5e5 001fa0e1 020080e3 1800c5e5 0600a0e1 a1bfa0e1 ??????eb 0090a0e1 1800d5e5 0210a0e3 8b1001e0 0200c0e3 010080e1` |
| 0x114354 | `album-artists` | `b802d8e1 000050e3 ??????0a 200094e5 04208de2 08108de2 ??????eb b832d8e1 08109de5 04209de5 00308de5 023c85e2 2a3083e2` |
| 0x193488 | `album-artists` | `70402de9 980090e5 0140a0e1 ??????eb 0050a0e1 0400a0e1 ??????eb 000015e0 0100a013 7080bde8 70402de9 ????9fe5 0250a0e1` |
| 0x19353c | `album-artists` | `980090e5 0270a0e1 0160a0e1 ??????eb 0050a0e1 0600a0e1 ??????eb 000057e3 0010c501 00108511 980094e5 f041bde8 ??????ea` |
| 0xe59a0 | `shuffle-fixes` | `010010e3 ??????1a 040084e2 ??????eb 000050e3 ??????0a ??????eb 080084e5 040084e2 ??????eb 0518a0e1 7040bde8 ????9fe5` |
| 0x1929a0 | `shuffle-album-mix` | `3c00a013 0000c6e5 7080bde8 f8402de9 0040a0e1 980090e5 ??????eb 1c00c4e5 980094e5 ??????eb 1d00c4e5 980094e5 ??????eb` |
| 0x193b9c | `shuffle-album-mix` | `7080bde8 ???????? ??????2a f8402de9 0040a0e1 980090e5 ??????eb 1c10d4e5 ????9fe5 000051e1 ??????0a 1c00c4e5 000094e5` |
| 0x191eb0 | `shuffle-album-mix` | `ff0000e2 020050e3 1c00c4e5 1c80c485 1c10d4e5 980094e5 ??????eb 000094e5 0720a0e1 543090e5 0400a0e1 0b10a0e1 0fe0a0e1` |
| 0x946d8 | `shuffle-fixes` | `01005013 ??????da 0a70a0e1 ??????ea 080047e0 010080e2 ??????eb 072186e0 103092e5 001186e0 100091e5 103081e5 017047e2` |
| 0x21f254 | `dark-mode`, `something-comforting`, `album-artists`, `shuffle-album-mix`, `up-next` | `050051e3 04005113 03005113 01005113 0000a013 1eff2fe1 f8402de9 0150a0e1 0010a0e3 0260a0e1 0040a0e1 00108de5 ??????ea` |
| 0x1eb5b4 | `up-next` | `???????? 65050000 10402de9 0040a0e1 0200b0e1 1c009405 ??????eb 000050e3 0000a013 1080bd18 0400a0e1 ??????eb 0100a0e3` |
| 0x9ee90 | Software version | `0040a0e1 0030a0e3 8000a0e3 00308de5 0030a0e1 08008de2 0110a0e3 3020a0e3 ??????eb 6420a0e3 24108de2 08008de2 ??????eb` |
| 0x9ee70 | Software version | `0b0c80e2 d304d0e1 1eff2fe1 a00c90e5 510bd0e5 1eff2fe1 10402de9 62df4de2 0040a0e1 0030a0e3 8000a0e3 00308de5 0030a0e1` |

The signatures of the methods for the vtable hooks. They start at the function entry (`MakeSignature.java OUT ADDRESS 0 12`), so the offset is 0:

| Method | Slot | Patch | Signature |
|---|---|---|---|
| 0x1bb260 | 0x66e470 | `album-art` | `f74f2de9 30d04de2 0040a0e1 741080e2 ??????eb 20108de2 0400a0e1 ??????eb 2c009de5 24109de5 14e08fe2 017040e0 000094e5` |
| 0x244924 | 0x677a14 | `album-art` | `30402de9 01e0a0e1 0040a0e1 c81094e5 0250a0e1 0820f1e5 c00090e5 24d04de2 2020cde5 0120d1e5 20c08de2 2120cde5 0220d1e5` |
| 0x1d83fc | 0x69fd2c | `sleep-now` | `10402de9 0040a0e1 180090e5 ??????eb 000050e3 18009415 ??????1b ??????eb 480084e2 ??????eb 480084e2 7d1fa0e3 ??????eb` |
| 0x190b00 | 0x66c94c | `dark-mode`, `something-comforting`, `album-artists`, `shuffle-album-mix`, `up-next` | `ff4f2de9 0050a0e1 0100a0e3 83df4de2 04028de5 ????9fe5 0080a0e3 000090e5 0160a0e1 010010e3 0340a0e1 ??????1a ????9fe5` |
| 0x1919d8 | 0x66c950 | `dark-mode`, `something-comforting`, `album-artists`, `up-next` | `f84f2de9 ????9fe5 0040a0e1 71c046e2 ????9fe5 0c0052e1 010086e2 01a0a0e3 0290a0e1 0080a0e3 0350a0e1 907046e2 ??????0a` |
| 0x19351c | (`b` at the entry) | `instant-save` | `f0412de9 0040a0e1 980090e5 0270a0e1 0160a0e1 ??????eb 0050a0e1 0600a0e1 ??????eb 000057e3 0010c501 00108511 980094e5` |
| 0x23ca4c | 0x6776f8 | `album-artists` | `????9fe5 ??????ea 43756e4d 70402de9 0040a0e1 440190e5 0150a0e1 000050e3 7080bd08 ??????eb 000050e3 0510a011 0400a011` |
| 0x23b704 | 0x6772c0 | `cover-flow` | `70402de9 0040a0e1 200090e5 0160a0e1 061b00e2 040096e5 020b51e3 0050a0e3 ??????1a 040050e3 05005013 ??????0a 090050e3` |
| 0x1d81cc | 0x6701f0 | `cover-flow` | `f0412de9 0040a0e1 040091e5 0150a0e1 030050e3 18009405 ??????0b 040095e5 040050e3 ??????1a 0500a0e1 ??????eb 000050e3` |
| 0x17ef98 | 0x17ef8c | `cover-flow` | `70402de9 0c0091e5 0140a0e1 041091e5 010050e1 080094c5 001094c5 010050c1 7080bdd8 000052e3 7080bd18 ????9fe5 ????9fe5` |

`FindConstant` finds 0x23b704 in three slots: 0x6671ac, 0x66eedc and 0x6772c0. The `cover-flow` patch uses only the slot of the browse-list class 0x677290 (vtable start + 0x30). 0x17ef8c is a literal in 0x17eeb0, not a vtable slot.

Two more sites of `album-artists` need a different window:

- 0xd7ea0 is an entry of a jump table (3573 matches). `MakeSignature.java OUT 0xd7e40 8 2` gives the dispatch: `10049de5 181040e2 0900a0e1 ??????eb 0050b0e1 ??????1a 18549de5 1f0055e3 05f18f90 ??????ea ??????ea` (1 match, offset 32). The hook site is the dispatch 0xd7e40 + 8 + 4 × 22.
- Function entries (`MakeSignature.java OUT ADDRESS 0 12`, offset 0, 1 match each): 0x1e7b98 `10402de9 0040a0e1 1c0090e5 0010a0e3 ??????eb 1c0094e5 0320a0e3 0110a0e3 ??????eb 0000e0e3 ec0384e5 000484e5 0000a0e3`; 0xa34b8 `70402de9 0040a0e1 480c90e5 0050a0e3 000050e3 ??????0a ??????eb 485c84e5 4c0c94e5 000050e3 ??????0a ??????eb 4c5c84e5`; 0x19ed58 `1c402de9 0240a0e1 0320a0e1 10309de5 0c008de8 002090e5 01e0a0e1 8cc192e5 0e20a0e1 241090e5 04e08fe2 0430a0e1 1cff2fe1`.
- 0xd080c is a function entry: `MakeSignature.java OUT 0xd080c 0 12` gives `ff5f2de9 96df4de2 0050a0e1 0000a0e3 4c008de5 0010e0e3 24008de5 48008de5 44008de5 0500a0e1 0090a0e3 0080a0e3 0070a0e3` (1 match, offset 0).

These signatures are a start point. A function that Apple changed between the versions does not match. Then use the recipes in section 3.
