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
0x131b84. The address 0x131b84 is not the start of a function. The function
that has the address 0x131b84 starts at 0x10131874. The address is at the
offset 0x310 of that function.

### The list of the strings

The command `rea search` with the kind `strings` gave 11,232 strings. The
research checked 7 strings that the other notes had found. The research of REA
confirmed all 7 of them. The table gives 5 of them.

| The address | The text |
|---|---|
| 0x4b2b18 | This game cannot be played. |
| 0x4b2ae4 | Connect your iPod to iTunes and reinstall the game. |
| 0x678dd6 | Verify |
| 0x2a9c3c | games_RO |
| 0x1b085c | eAppBlockMgr |

## The limits of the research

| The limit | The result |
|---|---|
| The image `hibe` | The image is a copy of the memory. The analysis needs more memory than the machine has. The image holds no code of the firmware. |
| The image `aupd` | The image is encrypted. The engine reads 1 function. The image holds no code that the engine can read. |
| The image `rsrc` | The image is a file system. The engine reads 1 function. |
| The names of the functions | The image has no symbols. The names `FUN_` and the address are the names of the image. The map of the strings gives 380 functions a name from their strings. |
| The size of the code | The C code of a function with many paths has the name `extraout_r1` many times. The logic of the code is still correct. |
| The functions of the library | The engine reads the functions of the library of C as external. The research skipped them. |

## The map of the strings

The research made the map of the strings. The map gives the name of each
function and the group of each function. The name comes from the strings that
the function uses.

### The method of the map

The decompiler does not give the text of a string. The decompiler gives the
address of the string. The research found 3 ways that the firmware reaches a
string.

| The way | The description |
|---|---|
| The name of the decompiler | The decompiler gives a string a name. The name starts with `s_` and ends with the address of the string. The address gives the text in the image. |
| The word of a literal pool | The firmware puts the number of a string in a word. The word is in a literal pool. The number is the id of a string in the table of the resources. The text comes from that table. |
| The table of the resources | The table of the resources of the image holds the strings. Each string has a number. The research read the table with the reader of the project, `ipodfw.resources.read_strings`. |

The first way gives 814 uses of a string. The second way gives 58 uses. The
research used 382 functions of the 14,411 functions. The functions use 841
different strings.

> The research first used the second way without a check. The check found that
> the way gives false results. The value -511 is the id of the string "This game
> cannot be played." The value is also a mask of the bits in a formula of a
> function of the video processor. The false result was the function
> `FUN_1003a89c`. The research now accepts a word only if the code passes the
> word to a call.

### The groups of the functions

The research put each function into a group. The group comes from the strings
that the function uses. The table has the rules of the groups. The first rule
that matches a string gives the group.

| The group | The functions with a string |
|---|---|
| Files and storage | 60 |
| System and services | 31 |
| Tools and build | 29 |
| Music and audio | 27 |
| Video and photo | 26 |
| DRM and FairPlay | 1 |
| No string | 206 |

The 14,029 other functions use no string that the research can find. These
functions are the parts of the library of C, the parts of the driver of the
hardware and the parts of the code that use no text.

### The functions with a name

The research named 380 functions. The name comes from the longest string that
the function uses. The name has only the letters, the digits and the
underscore. The file `osos-function-names.tsv` has the name of each function.

The names show the parts of the firmware.

| The address | The name | The group |
|---|---|---|
| `10093ea0` | `iPod_Control` | Files and storage |
| `10093ee0` | `iPod_Control_Device` | Files and storage |
| `1009400c` | `Photo_Database` | Video and photo |
| `1009483c` | `TrackCacheReadTask` | Music and audio |
| `100a25b4` | `iPod_Control_Device_SysInfo` | Files and storage |
| `100b78b8` | `iPod_Control_Music` | Music and audio |
| `100bbf1c` | `iPod_Control_Device_Preferences` | Files and storage |
| `100c22b4` | `FAT12` | Files and storage |
| `100d1434` | `APPLE_HFS` | Files and storage |
| `100d3b44` | `t_graphicsManager` | System and services |
| `100db0fc` | `iMABlockManagerThread` | System and services |
| `100de9d8` | `ICAPTPCameraIOTask` | System and services |
| `100e2aa4` | `Add_Interface_for_device_lx_VID_d_PID_d` | System and services |
| `100ebd84` | `iPod_Control_iTunes_Play_Counts` | Music and audio |
| `10148108` | `PowerManager` | System and services |
| `10148ca4` | `RtcTaskClass` | System and services |
| `10151568` | `TimerEventManager` | System and services |
| `10155e7c` | `SearchHelperThread` | System and services |
| `10158124` | `TcMemManagerThread` | System and services |
| `1016b0b0` | `MP3ExampleTask` | Music and audio |
| `10165164` | `VCUpdateTask` | System and services |
| `10170fec` | `USBDeviceTask` | System and services |
| `101d62d4` | `CIapIncomingProcessThread` | System and services |
| `101d73e4` | `CIapOutgoingProcessThread` | System and services |
| `101e804c` | `Now_Playing` | Music and audio |
| `101fb7a4` | `FAT32` | Files and storage |
| `1020be1c` | `StreamCacheReadTask` | System and services |
| `102860e8` | `USBTaskTimeTask` | System and services |

> The names of the threads show the tasks of the system. The tasks of the
> video, the camera, the interface of the computer and the disk all have a
> name in the code.

### The table of the strings

The file `osos-strings.tsv` has each string and the functions that use the
string. The table has 841 rows. The file `osos-string-map.tsv` has the use of
each string in each function. The file has 872 rows.

The strings that the most functions use are the strings of the format.

| The string | The functions | The use |
|---|---|---|
| `%02d:%02d:%02d.%03d` | 5 | The time of the log. |
| `%s, %s %s` | 4 | The name of a file with the path. |
| `STANDARD` | 4 | The state of a task. |
| `configuration complete - numluns is %d` | 3 | The state of the disk. The text has a new line at the end. |
| `Season %d` | 3 | The season of a show of the television. |
| `Roll #%d` | 3 | The number of the photo. |
| `Error inside %s` | 2 | The error of a part of the system. |

### The files of the map

The research writes the files of the map in the folder
`~/Library/Application Support/iPodFirm/re/retailos-1.3-decompiled`. The
folder is not in the repository. The folder holds the image of the firmware.

| The file | The content |
|---|---|
| `osos-strings.c` | The C code of every function. The code has the name of every string. |
| `osos-string-map.tsv` | Each function and each string that the function uses. |
| `osos-function-names.tsv` | Each function with its name and its group. |
| `osos-strings.tsv` | Each string and the functions that use the string. |
| `string-pointers.tsv` | Each word that holds the address of a string. |

### The limits of the map

| The limit | The result |
|---|---|
| The number of the functions with a string | 382 of the 14,411 functions. The other functions use no text, or they reach the text in a way that the research did not find. |
| The false results of the literal pool | The check of the call removes the false results. The check is a rule, not a proof. |
| The strings of the other languages | The image has 25 blocks of the resources. Each block has the strings of one language. The map uses the main block. |
| The names of the functions | The name comes from the longest string. The name is often not the name of the function. The name is a hint. |
| The groups of the functions | The group comes from the strings. A function of the group "Files and storage" can work on the music. |

## The next steps

| The step | The work |
|---|---|
| 1 | Use the map of the strings to name the functions of the user interface. The name of the function must come from the class and from the method of the object. |
| 2 | Read the strings of the other languages. The map must have the string of every language. |
| 3 | Make the map of the classes. The image has the tables of the methods. The table of each class gives the methods. |

## The sources of the research

| The source | The use |
|---|---|
| The image `osos` at `~/Library/Application Support/iPodFirm/re/osos-1.3.bin` | The code of the firmware. |
| The tool REA, the provider for Ghidra 12.1.4 | The analysis and the dossiers. |
| The script [ghidra-scripts/DecompileAll.java](ghidra-scripts/DecompileAll.java) | The decompilation of every function. |
| The script [ghidra-scripts/DefineStringPointers.java](ghidra-scripts/DefineStringPointers.java) | The type of the words that hold the address of a string. |
| The script [ghidra-scripts/DecompileWithStrings.java](ghidra-scripts/DecompileWithStrings.java) | The decompilation of every function with the name of every string. |
| The script [make-function-index.py](make-function-index.py) | The table of the functions. |
| The script [make-string-map.py](make-string-map.py) | The map of the strings. |
| The script [decompile-with-strings.sh](decompile-with-strings.sh) | The whole run of the map. |
| The module `ipodfw.resources` of the project | The table of the resources of the image. |
| The note [ghidra.md](ghidra.md) | The use of Ghidra in this project. |
