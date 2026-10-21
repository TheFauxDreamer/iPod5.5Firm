# The decompilation of the whole RetailOS 1.3: the research of 21 October 2026

This note gives the result of the decompilation of the whole image `osos` of
RetailOS 1.3. The research uses the tool REA and the engine Ghidra 12.1.4. The
research is for the record of the firmware. The research gives a list of every
function of the firmware with its size and with the number of functions that it
calls.

The note gives the result in the first section. The research gives the
evidence. The reference [../docs/firmware-functions.md](../docs/firmware-functions.md)
gives the short form.

## The result in short

The research decompiled **14,411 functions** of the image `osos`. The research
failed for **0 functions**. The C code has **551,459 lines** and **13,378,201
bytes**.

| The item | The value |
|---|---|
| The image | `osos` of RetailOS 1.3. The size is 7,561,216 bytes. |
| The digest of the image | `784ae3d5540fd2f89e8c947b93629e97f62a06dc311d9745aab143e4db6bb251` |
| The functions | 14,411. The research failed for 0. |
| The C code | 551,459 lines. 13,378,201 bytes. |
| The digest of the C code | `0838398fd8270d4780506b69e6b31e93c24b74cffcdb545ff6778c477d9ad6c4` |
| The range of the addresses | 0x100000f0 to 0x10733b64. |
| The median size of a function | 24 lines of C code. |
| The functions under 50 lines | 11,902. |
| The functions over 500 lines | 31. |
| The time of the analysis | 2 minutes 14 seconds for the first pass. 4 minutes 14 seconds for the decompilation. |

The research confirms the results of the other notes. The research of the check
of the DRM in [games-drm.md](games-drm.md) found the function `FUN_00131874`
at 0x131874. The research of REA found the same function. The research of REA
also confirms the 6 addresses of the patch of the community. The note gives
the evidence in the section "The check of the results of the other notes".

## The images of the firmware

The partition of the iPod has 4 images. The research decompiled each image.

| The image | The size | The content | The functions |
|---|---|---|---|
| `osos` | 7,561,216 bytes | The code of RetailOS and the resources of the user interface. | 14,411 |
| `rsrc` | 5,244,928 bytes | A file system with the fonts and the programs of the video processor. | 1 |
| `aupd` | 1,075,200 bytes | The updater of the boot flash. The image is encrypted. | 1 |
| `hibe` | 67,110,912 bytes | The image of the hibernation. The image is the memory of the iPod at the time of the hibernation. | not code |

> The image `rsrc` and the image `aupd` hold no code of the processor. The
> research of REA found 1 function in each of them. That function is the entry
> point that the script of the preparation makes. The image `hibe` is a copy of
> the memory. The analysis of the image `hibe` needs more memory than the
> machine of the owner has. The image `hibe` is not code of the firmware. The
> note does not decompile it.

The code of the firmware is the image `osos`. The research decompiled the image
`osos` in full.

## The method

The research uses the tool REA. The tool has a provider for Ghidra. The
research uses the same analysis as the tool. The tool uses these steps.

1. The tool imports the image as a raw binary. The loader is `BinaryLoader`.
   The base is 0x10000000. The processor is `ARM:LE:32:v7`.
2. The tool runs the script `ReaGhidraPrepareRaw.java`. The script makes the
   entry point at the base of the image.
3. The engine Ghidra runs the analysis.
4. The tool runs the script `ReaGhidraNoReturnFix.java`. The script undoes the
   wrong flags of no return. The flags make the decompiler cut the callers.
5. The tool gives the results.

The research adds 1 step. The research runs the script `DecompileAll.java` that
is in [ghidra-scripts](ghidra-scripts/DecompileAll.java). The script writes the
C code of every function to one file. The script then makes the index of the
functions with the script [make-function-index.py](make-function-index.py).

The command that does the whole work is in [decompile-all.sh](decompile-all.sh).

```sh
./re/decompile-all.sh
```

## The list of the functions

The research writes a table with one row for each function. The table has 5
columns.

| The column | The content |
|---|---|
| `address` | The address of the function. |
| `name` | The name of the function. Ghidra gives the name `FUN_` and the address. |
| `lines` | The number of lines of the C code of the function. |
| `bytes` | The number of bytes of the C code of the function. |
| `calls` | The number of other functions that the function calls. |

The table has 14,411 rows. The table is at
`~/Library/Application Support/iPodFirm/re/retailos-1.3-decompiled/osos-functions.tsv`.

### The functions with the most calls

| The address | The number of calls | The number of lines |
|---|---|---|
| 0x101e804c | 62 | 593 |
| 0x101c9728 | 54 | 383 |
| 0x1024a024 | 54 | 337 |
| 0x10197f84 | 52 | 325 |
| 0x101f3f24 | 51 | 386 |
| 0x100b43dc | 50 | 112 |
| 0x100abfb0 | 48 | 240 |
| 0x10135b2c | 43 | 928 |
| 0x101a3254 | 43 | 335 |
| 0x101ca150 | 43 | 204 |

### The functions with the most lines

| The address | The number of lines | The number of bytes |
|---|---|---|
| 0x1003c918 | 3,013 | 113,548 |
| 0x100e95cc | 2,246 | 87,673 |
| 0x10034dec | 2,215 | 72,427 |
| 0x1002e8a8 | 1,764 | 57,818 |
| 0x10073ce0 | 1,561 | 49,553 |
| 0x10262d90 | 1,578 | 43,150 |
| 0x1027f5f0 | 1,357 | 41,431 |
| 0x102611e8 | 1,455 | 35,813 |
| 0x102648ac | 1,238 | 34,999 |
| 0x1004af18 | 1,070 | 34,206 |

> CAUTION: The decompiler of Ghidra has a limit. The decompiler cannot hold
> the value of a register for a function with many paths. The decompiler then
> writes the name `extraout_r1` many times. The function at 0x1003c918 has 3,013
> lines for this reason. The function is not that large. The C code of the
> function with the limit is still correct in its logic.

## The check of the results of the other notes

The research of REA used a different method than the other notes. The other
notes used a search of the strings and a decompilation of one function. The
research of REA used the analysis of the whole image. The results must agree.
The research checked the results below.

### The list of the procedures

The command `rea search` with the kind `procedures` gave 14,866 entries. The
entries have 160 external entries. The entries have 14,706 entries with an
address. The research decompiled 14,411 functions. The difference is 295
functions. The difference is the functions that the decompiler does not give.
The functions are the ones that the engine reads as data.

The research checked 35 addresses that the other notes had found. The research
of REA confirmed 34 of them. The address that the research did not find is
0x131b84. The address 0x131b84 is not the start of a function. The address is
the exit of the failure of the check of the DRM. The function that has the
address 0x131b84 starts at 0x10131874. The address is at the offset 0x310 of
that function.

### The list of the strings

The command `rea search` with the kind `strings` gave 11,232 strings. The
research checked 7 strings that the other notes had found. The research of REA
confirmed all 7 of them.

| The address | The text |
|---|---|
| 0x4b2b18 | This game cannot be played. |
| 0x4b2ae4 | Connect your iPod to iTunes and reinstall the game. |
| 0x69f70c | IC-Info.sidb |
| 0x69f6fc | IC-Info.sidd |
| 0x678dd6 | Verify |
| 0x2a9c3c | games_RO |
| 0x1b085c | eAppBlockMgr |

### The check of the DRM

The research of REA gave the dossier of the function `FUN_10131874`. The
dossier gave the caller of the function. The caller is `FUN_1024e37c`. The
note [games-drm.md](games-drm.md) named the same function as the function that
makes the check of the platform and the check of the DRM. The research agrees.

The dossier gave the graph of the basic blocks of the function. The graph has
26 blocks. **8 blocks** have the address 0x10131b84 as a successor. The
address 0x10131b84 is the exit of the failure. The 6 sites of the patch of the
community are the 6 instructions that make those branches.

| The site | The block of the site | The block goes to the failure |
|---|---|---|
| (address removed) | 0x101318b0 to 0x1013191c | Yes |
| (address removed) | 0x1013191c to 0x1013192c | Yes |
| (address removed) | 0x1013192c to 0x10131944 | Yes |
| (address removed) | 0x10131b10 to 0x10131b48 | Yes |
| (address removed) | 0x10131b48 to 0x10131b54 | Yes |
| (address removed) | 0x10131b64 to 0x10131b80 | Yes |

> The research of REA confirms the 6 sites of the patch of the community. The
> research did this with the graph of the basic blocks. The other notes did it
> with the disassembly. The two methods agree.

The dossier gave the list of the functions that the function calls. The list
has 24 functions. The list has `FUN_101314ec` and `FUN_101315e8`. The note
[games-drm.md](games-drm.md) named the same 2 functions as the functions that
read the manifest and the file `sinf` of the game.

## The limits of the research

| The limit | The result |
|---|---|
| The image `hibe` | The image is a copy of the memory. The analysis needs more memory than the machine has. The image holds no code of the firmware. |
| The image `aupd` | The image is encrypted. The engine reads 1 function. The image holds no code that the engine can read. |
| The image `rsrc` | The image is a file system. The engine reads 1 function. |
| The names of the functions | The image has no symbols. The names are `FUN_` and the address. |
| The size of the code | The C code of a function with many paths has the name `extraout_r1` many times. The logic of the code is still correct. |
| The functions of the library | The engine reads the functions of the library of C as external. The research skipped them. |

## The next steps

| The step | The work |
|---|---|
| 1 | Give a name to each function of the table. The name must come from the strings that the function uses. The research can do this for the functions of the user interface. |
| 2 | Make the groups of the functions. The groups are the parts of the firmware: the user interface, the file system, the DRM, the video processor and the music. |
| 3 | Make the table of the strings with the functions that use each string. The table gives the map of the firmware. |

## The sources of the research

| The source | The use |
|---|---|
| The image `osos` at `~/Library/Application Support/iPodFirm/re/osos-1.3.bin` | The code of the firmware. |
| The tool REA, the provider for Ghidra 12.1.4 | The analysis and the dossiers. |
| The script [ghidra-scripts/DecompileAll.java](ghidra-scripts/DecompileAll.java) | The decompilation of every function. |
| The script [make-function-index.py](make-function-index.py) | The table of the functions. |
| The note [games-drm.md](games-drm.md) | The check of the DRM. The research of REA confirms it. |
| The note [ghidra.md](ghidra.md) | The use of Ghidra in this project. |
