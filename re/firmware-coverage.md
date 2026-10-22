# The reverse engineering of the firmware: the index and the state of the research

This note is the map of the reverse engineering of the firmware of the iPod
Video. The note gives the list of every part of the firmware. The note gives
the state of the research for each part.

> The firmware is **not** fully reverse engineered. The research covers 5.3% of
> the functions of the code and 10.2% of the lines. The research names 2.6% of
> the parts of the user interface. The rest of the firmware is known to exist
> and is mapped, but its behaviour is not documented.

The note has 5 parts.

| The part | The content |
|---|---|
| [The images](#the-images) | The 4 images of the partition of the iPod. |
| [The parts of the user interface](#the-parts-of-the-user-interface) | The 2,214 parts of the table of the resources. |
| [The state of the code](#the-state-of-the-code) | The 14,411 functions of the image `osos`. |
| [The notes](#the-notes) | The 30 notes of the research and what each note covers. The note of the systems is at [firmware-systems.md](firmware-systems.md). |
| [The systems](firmware-systems.md) | The systems and the sub-systems of the firmware. The 7 systems, the 21 tasks of the firmware and the 222 tables of the classes. |
| [The task system](firmware-task-system.md) | The kernel of the firmware. The base class of the tasks, the object of a task, the 9 classes of the priority and the scheduler. |
| [The warnings](#the-warnings) | The limits of the research. The names are not real names. |

## The images

The partition of the iPod has 4 images. The research decompiled each image.

| The image | The size | The content | The state of the research |
|---|---|---|---|
| `osos` | 7,561,216 bytes | The code of RetailOS and the resources of the user interface. | **Fully decompiled.** 14,411 functions, 0 failures. 10.2% of the code has a note. |
| `rsrc` | 5,244,928 bytes | A file system with the fonts and the programs of the video processor. | **Not researched.** The image holds no code of the processor. |
| `aupd` | 1,075,200 bytes | The updater of the boot flash. The image is encrypted. | **Not researched.** The image is encrypted. The research cannot read it. |
| `hibe` | 67,110,912 bytes | The image of the hibernation. The image is the memory of the iPod at the time of the hibernation. | **Not code.** The image is a copy of the memory. The analysis needs more memory than the machine has. |

> The code of the firmware is the image `osos`. The research decompiled the
> image `osos` in full. The other 3 images hold no code that the processor can
> run. The image `rsrc` holds the programs of the video processor. These
> programs run on a separate processor.

## The parts of the user interface

The image `osos` holds a table of the resources. The table is the list of the
parts of the user interface. The script
[make-firmware-inventory.py](make-firmware-inventory.py) reads the table. The
script found 2,214 parts.

| The type | The meaning | The parts | The parts with a note | The share |
|---|---|---|---|---|
| `Str ` | The strings of the text of the interface. | 991 | 0 | 0.0% |
| `View` | The screens. Each view has a layout of the elements. | 619 | 4 | 0.6% |
| `BMap` | The pictures of the elements. | 402 | 5 | 1.2% |
| `Type` | The class of each view. | 158 | 0 | 0.0% |
| `Menu` | The menus and their items. | 40 | 6 | 15.0% |
| `Bits` | The bitmaps of the small pictures. | 1 | 0 | 0.0% |
| `LDTm` | The load times. | 1 | 0 | 0.0% |
| `TCmd` | The table of the commands. | 1 | 0 | 0.0% |

The menus have the most research. The project uses the menus for the patches.
The `settings_items` and the `menu_items` of the patch system need the number
of the menu. Refer to [../docs/patch-system.md](../docs/patch-system.md).

The table of the parts is in the file `firmware-parts.tsv`. The script writes
the file. The file has the type, the number, the size, the offset and the notes
of every part.

### The parts that the notes name

| The type | The number | The part | The notes |
|---|---|---|---|
| `View` | 24069 | The root of the screen. | dark-theme, firmware-functions, modifications |
| `View` | 24484 | The screen of the albums. | firmware-functions |
| `View` | 24486 | The screen of the artists. | album-artist, firmware-functions |
| `View` | 24506 | The title bar. | album-artist, dark-theme, firmware-functions, modifications |
| `BMap` | 24268 | The picture of the element. | firmware-functions |
| `BMap` | 24273 | The picture of the element. | firmware-functions |
| `BMap` | 24342 | The layout of the screen. | README, firmware-functions |
| `BMap` | 24351 | The picture of the element. | firmware-functions |
| `BMap` | 24379 | The picture of the title bar. | dark-theme, firmware-functions, modifications |
| `Menu` | 24094 | The main menu. | album-artist, firmware-functions, modifications, patch-system, usb-host |
| `Menu` | 24440 | The menu of the music. | album-artist, firmware-format, firmware-functions, patch-system |
| `Menu` | 24598 | The menu of the settings. | dark-theme, firmware-format, firmware-functions, modifications, patch-system, usb-host |
| `Menu` | 24600 | The menu of the main menu in the settings. | album-artist, firmware-functions, patch-system, song-info |
| `Menu` | 24604 | The menu of the daylights. | firmware-functions, patch-system, play-next |
| `Menu` | 24610 | The menu of the song. | song-info |

> The other 2,199 parts of the table have no note. The project can use each of
> them. The script reads the whole table. A new feature of the user interface
> usually needs 1 view, 1 menu and a few strings.

## The state of the code

The image `osos` has 14,411 functions. The research decompiled all of them.
The research read the code of 760 of them.

| The measure | The value |
|---|---|
| The functions in the image | 14,411 |
| The functions with a note | 760 (5.3%) |
| The lines of the C code | 551,459 |
| The lines with a note | 56,411 (10.2%) |
| The functions with a name from their strings | 380 (2.6%) |
| The functions with a string | 382 (2.7%) |

The table of the code that the notes name is in the file
`firmware-code-coverage.tsv`. The script writes the file. The file has the
number of the functions and the number of the lines for each note.

### The functions with the most research

| The note | The functions | The lines | The share of the code |
|---|---|---|---|
| [firmware-functions.md](../docs/firmware-functions.md) | 521 | 27,301 | 5.0% |
| [usb-host.md](usb-host.md) | 258 | 12,095 | 2.2% |
| [../docs/modifications.md](../docs/modifications.md) | 168 | 8,926 | 1.6% |
| [shuffle.md](shuffle.md) | 69 | 5,855 | 1.1% |
| [album-artist.md](album-artist.md) | 57 | 4,964 | 0.9% |
| [custom-eq.md](custom-eq.md) | 39 | 4,334 | 0.8% |
| [cover-flow.md](cover-flow.md) | 51 | 3,672 | 0.7% |
| [games.md](games.md) | 52 | 2,792 | 0.5% |
| [list-rendering.md](list-rendering.md) | 24 | 2,239 | 0.4% |
| [play-next.md](play-next.md) | 41 | 1,909 | 0.3% |
| [games-drm.md](games-drm.md) | 34 | 1,487 | 0.3% |
| [album-art-v2.md](album-art-v2.md) | 22 | 1,470 | 0.3% |
| [dark-theme.md](dark-theme.md) | 17 | 1,464 | 0.3% |
| [play-latency.md](play-latency.md) | 34 | 1,323 | 0.2% |
| [song-info.md](song-info.md) | 8 | 1,219 | 0.2% |
| [backlight-timer.md](backlight-timer.md) | 8 | 1,194 | 0.2% |
| [sleep.md](sleep.md) | 32 | 1,124 | 0.2% |
| [games-keys.md](games-keys.md) | 30 | 1,041 | 0.2% |
| [usb-audio.md](usb-audio.md) | 23 | 928 | 0.2% |
| [games-plans.md](games-plans.md) | 17 | 653 | 0.1% |
| [languages.md](languages.md) | 23 | 570 | 0.1% |
| [volume-limit.md](volume-limit.md) | 7 | 584 | 0.1% |
| [games-real-ipod.md](games-real-ipod.md) | 10 | 346 | 0.1% |
| [piezo.md](piezo.md) | 8 | 264 | 0.0% |
| [ipod-classic-6g.md](ipod-classic-6g.md) | 3 | 198 | 0.0% |

### The parts of the firmware without research

The research did not document these parts of the firmware. Each part of the
list is a large area of work.

| The part | The size of the work |
|---|---|
| The USB device stack of the iPod as a device | The `usb-host.md` note covers the host side. The device side has no note. |
| The video processor of Broadcom | The programs are in the image `rsrc`. The research did not analyse them. |
| The file system | The `HFS` and the `FAT` have no note. The notes use them. |
| The power and the sleep of the system | The `sleep.md` note has 32 functions. The rest has no note. |
| The equalizer of the audio | The `custom-eq.md` note has 39 functions. The rest has no note. |
| The class system of the user interface | The 158 `Type` resources have no note. The methods of the classes have no note. |
| The library of C and the drivers of the hardware | The 14,029 functions without a string. Most of them are here. |

## The notes

The research has 30 notes. Each note is in the folder `re`. This note and the
note [firmware-systems.md](firmware-systems.md) and the note
[firmware-task-system.md](firmware-task-system.md) are the other 3 files of the
folder. The table gives what each note covers.

| The note | The part of the firmware | The state |
|---|---|---|
| [retailos-decompile.md](retailos-decompile.md) | The whole image `osos`. The decompilation, the map of the strings, the groups of the functions. | Complete for the code. |
| [games.md](games.md) | The games of the iPod. The formats, the files, the install. | Complete. |
| [games-drm.md](games-drm.md) | The check of the DRM in the firmware. The 2 functions, the 6 sites of the patch of the community. | Complete. |
| [games-keys.md](games-keys.md) | The file of the keys `IC-Info.sidb`. | Complete. |
| [games-plans.md](games-plans.md) | The 3 plans for the games. | Complete. |
| [games-real-ipod.md](games-real-ipod.md) | The games on a real iPod. The manifest, the folder, the file of the keys. | Complete. |
| [games-vm.md](games-vm.md) | The virtual machine of the community that installs the games. | Complete. |
| [usb-host.md](usb-host.md) | The USB host stack. The driver list, the descriptors, the transfers. | 258 functions. The most complete note. |
| [usb-audio.md](usb-audio.md) | The USB audio in the firmware. | 23 functions. |
| [usb-adapter.md](usb-adapter.md) | The plan for the USB-C adapter. | A plan, not a research. |
| [shuffle.md](shuffle.md) | The shuffle of the music. The 3 modes, the model. | 69 functions. |
| [album-artist.md](album-artist.md) | The artist of the album. The reading and the writing of the file. | 57 functions. |
| [album-art-v2.md](album-art-v2.md) | The picture of the album, the version 2 of the file. | 22 functions. |
| [list-rendering.md](list-rendering.md) | The picture of the album in the list of the albums. | 24 functions. |
| [cover-flow.md](cover-flow.md) | The Cover Flow. | 51 functions. |
| [custom-eq.md](custom-eq.md) | The equalizer of the firmware 1.3. | 39 functions. |
| [play-next.md](play-next.md) | The Play Next and the Play Last. | 41 functions. |
| [play-latency.md](play-latency.md) | The delay of the play after the idle time. | 34 functions. |
| [song-info.md](song-info.md) | The data of the song in the interface. | 8 functions. |
| [languages.md](languages.md) | The languages of the image. | 23 functions. |
| [dark-theme.md](dark-theme.md) | The dark theme. The views and the pictures. | 17 functions. |
| [dark-mode-compression.md](dark-mode-compression.md) | The table of the switch of the dark mode. | The data only. |
| [backlight-timer.md](backlight-timer.md) | The timer of the backlight. | 8 functions. |
| [sleep.md](sleep.md) | The sleep of the system. | 32 functions. |
| [piezo.md](piezo.md) | The piezo of the click wheel. | 8 functions. |
| [volume-limit.md](volume-limit.md) | The limit of the volume of the EU. | 7 functions. |
| [emulator.md](emulator.md) | The test of a changed firmware in the emulator. | The method. |
| [ghidra.md](ghidra.md) | The load of the image in Ghidra. | The method. |
| [ipod-classic-6g.md](ipod-classic-6g.md) | The firmware 1.1.2 of the iPod classic. | 3 functions. |
| [patch-ideas.md](patch-ideas.md) | The ideas for the patches. | A list, not a research. |

The guide of the use of Ghidra is in [../docs/ghidra-guide.md](../docs/ghidra-guide.md).
The list of the addresses of the firmware is in
[../docs/firmware-functions.md](../docs/firmware-functions.md).

## The warnings

> Read this part before you use a name or an address of this research.

### The names of the functions are not real names

The image has no symbols. Every function has the name `FUN_` and its address.
This is the name of the analysis tool, not the name of Apple.

The script [make-string-map.py](make-string-map.py) gives 380 functions a name.
The name comes from the longest string that the function uses. The name is a
hint for the person who reads the code. It is not a name of Apple.

| The real name | The name of the research | The problem |
|---|---|---|
| `FUN_10093ea0` | `iPod_Control` | The function makes the folder of the iPod. The string is the name of the folder. |
| `FUN_100c22b4` | `FAT12` | The function works with the file system. The string is the name of the file system. |
| `FUN_10175c74` | `AutoRebootAfterFirmwareUpdate` | The function is the table of the atoms of the DRM. The longest string is a sentence of the update. |

The group of a function has the same problem. A function of the group "Files
and storage" can work on the music. The group comes from the strings.

### The addresses have 2 forms

The notes write the address as the offset into the image. The example is
`0x0b3a04`. The table of the functions writes the address with the base of the
memory. The example is `100b3a04`. The script
[make-firmware-inventory.py](make-firmware-inventory.py) removes the base from
the address of the table. The two forms then agree.

> The Ghidra project `osos13` uses the base 0x0. The decompilation of the whole
> image uses the base 0x10000000. The same function has 2 addresses in this
> project. Check the base before you compare 2 addresses.

### The names of the strings are truncated

The decompiler gives a string the name `s_<text>_<address>`. The name has the
text of the string, but the name replaces each run of characters that is not a
letter or a digit with an underscore. The name also has a limit of the length.
The script [make-string-map.py](make-string-map.py) reads the true text from the
image.

### The pool of the literal has no type

Ghidra does not follow a word that has no data type. Many words of the image
hold the address of a string. The decompiler shows the word as `DAT_` and the
address. The word is not a string.

The script [ghidra-scripts/DefineStringPointers.java](ghidra-scripts/DefineStringPointers.java)
gives the type of a pointer to every word that holds the address of a string.
The decompiler then names the string. The script raises the number of the named
strings from 794 to 11,232.

### The value of a word can be a false result

The firmware puts the number of a string in a word of a literal pool. The
number -511 is the id of the string "This game cannot be played." The same
value is also a mask of the bits in a formula of the video processor. The tool
that makes the map accepts a word only if the code passes the word to a call.

### The code of the decompiler has limits

The decompiler gives the name `extraout_r1` many times in a function with many
paths. This is a limit of the decompiler. The logic of the code is correct.

The analysis of the image `hibe` needs more memory than the machine has. The
image is a copy of the memory of the iPod. The image holds no code of the
firmware.

## The scripts of the research

| The script | The use |
|---|---|
| [decompile-all.sh](decompile-all.sh) | Decompiles the whole image `osos`. It writes the C code and the index of the functions. |
| [decompile-with-strings.sh](decompile-with-strings.sh) | Decompiles the whole image `osos` and makes the map of the strings. |
| [make-function-index.py](make-function-index.py) | Makes the table of the functions from the C code. |
| [make-string-map.py](make-string-map.py) | Makes the map of the strings, the names of the functions and the groups. |
| [make-firmware-inventory.py](make-firmware-inventory.py) | Makes the inventory of the parts of the firmware and the table of the state of the research. |
| [make-systems-map.py](make-systems-map.py) | Makes the list of the systems, the groups and the table of the tasks of the firmware. |
| [make-class-map.py](make-class-map.py) | Makes the list of the tables of the classes and their methods. |
| [ghidra-scripts/DecompileAll.java](ghidra-scripts/DecompileAll.java) | Writes the C code of every function. |
| [ghidra-scripts/DecompileWithStrings.java](ghidra-scripts/DecompileWithStrings.java) | Writes the C code of every function with the name of every string. |
| [ghidra-scripts/DefineStringPointers.java](ghidra-scripts/DefineStringPointers.java) | Gives the type of a pointer to the words that hold the address of a string. |
| [find-pattern.py](find-pattern.py) | Finds a byte pattern in a raw file without Ghidra. |

The files of the results are in `~/Library/Application Support/iPodFirm/re/retailos-1.3-decompiled/`.
The folder is not in the repository. The folder holds the image of the firmware.

| The file | The content |
|---|---|
| `osos.c` | The C code of every function. |
| `osos-strings.c` | The C code of every function with the name of every string. |
| `osos-functions.tsv` | The address, the name, the lines, the bytes and the calls of every function. |
| `osos-string-map.tsv` | Each function and each string that the function uses. |
| `osos-function-names.tsv` | Each function with its name and its group. |
| `osos-strings.tsv` | Each string and the functions that use the string. |
| `string-pointers.tsv` | Each word that holds the address of a string. |
| `firmware-parts.tsv` | Each part of the table of the resources and the notes that name it. |
| `firmware-types.tsv` | The number of the parts of each type and the number with a note. |
| `firmware-code-coverage.tsv` | The number of the functions and the lines of each note. |

## The next steps

| The step | The work |
|---|---|
| 1 | Make the inventory of the classes. The 158 `Type` resources give the class of each view. The table of the methods of each class gives the behaviour. |
| 2 | Read the strings of the other languages. The image has 25 blocks of the resources. The map of the strings has only the main block. |
| 3 | Name the functions of the user interface. The name must come from the class and from the method of the object. The strings give only a hint. |
| 4 | Make the map of the code that the notes do not name. The table of the functions has the number of the calls. The order of the calls gives the structure. |
