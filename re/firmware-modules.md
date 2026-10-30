# The modules of the screen of RetailOS 1.3

This note gives the research of the table of the modules of the screen. The
research is the part of the system "The user interface" of the note
[firmware-systems.md](firmware-systems.md). The note
[firmware-ui.md](firmware-ui.md) gives the resources of the screens and the
classes of the screens.

The addresses are the offsets in the image of the osos. The CPU address of the
code is the offset plus 0x10000000. The note uses the offset.

> This note is the research of the decompilation project. The notes of the
> earlier research stay as they are.

## The summary

The engine of the screen loads its modules from a table in the image. The
table has 7 modules. The table has 418 methods.

The table is in the resource section of the image. The table is not in the
code section. The research found the table by its magic.

## The table of the modules

The table is in the region 0x79474 to 0x79ce0. Each record of the table has
the same layout. The record starts with a magic of 4 bytes. The magic is
0x13061973. The bytes of the magic are the letters `s` and the numbers
0x19, 0x06 and 0x13.

| The offset of the record | The content | The size |
|---|---|---|
| +0x00 | The magic 0x13061973. | 4 |
| +0x04 | The name of the module. The name ends with a zero byte. | 0x24 |
| +0x28 | The flag of the record. The value is 1 for the 7 records. | 4 |
| +0x2c | The number of the methods of the module. | 4 |
| +0x30 | The address of the name of the next record. | 4 |
| +0x34 | The addresses of the methods. The table has the number of methods of the record. | 4 each |

The 7 records of the table are the following.

| The record | The module | The methods | The next record |
|---|---|---|---|
| 0x79474 | `OpenGLES` | 179 | 0x7978c |
| 0x79784 | `Filesytem` | 4 | 0x797e0 |
| 0x797d8 | `Audio` | 61 | 0x79918 |
| 0x79910 | `Metadata` | 152 | 0x79bbc |
| 0x79bb4 | `AsyncFileIO` | 17 | 0x79c44 |
| 0x79c3c | `InputEvents` | 2 | 0x79c90 |
| 0x79c88 | `Settings` | 3 | 0x79ce0 |

The table has 418 methods. The name of the module `OpenGLES` is at the image
0x7947c. The name of the module `Filesytem` is at 0x7978c. The name of the
module `Audio` is at 0x797dc. The name of the module `Metadata` is at
0x79918. The name of the module `AsyncFileIO` is at 0x79bb8. The name of the
module `InputEvents` is at 0x79c40. The name of the module `Settings` is at
0x79c8c.

> The name of the module `Filesytem` has a mistake. The name has the letter `y`
> in the place of the letter `s`. The name is in the image. The research did
> not change the name.

## The methods of the modules

The methods of the modules are in the region 0x2680c8 to 0x27513c. The
methods are the functions that the engine calls.

| The module | The first method | The last method |
|---|---|---|
| `OpenGLES` | 0x26c534 | 0x27513c |
| `Filesytem` | 0x26837c | 0x2684c8 |
| `Audio` | 0x26a20c | 0x26a848 |
| `Metadata` | 0x2695c4 | 0x269f04 |
| `AsyncFileIO` | 0x2680e4 | 0x26821c |
| `InputEvents` | 0x268320 | 0x26a8bc |
| `Settings` | 0x2686a8 | 0x26a884 |

The module `OpenGLES` has the most methods. The module has the 179 methods
of the drawing of the screen. The module `Metadata` has the 152 methods of
the data of the music and of the video.

The module `InputEvents` has 2 methods. The methods are at 0x268320 and at
0x26a8bc. The module `Settings` has 3 methods. The methods are at 0x2686a8 and
twice at 0x26a884.

## The engine of the screen

The function 0x1fc128 makes the object of the engine of the screen. The
function calls the function 0x22463c with the name "ImagePresentationEngine"
at the image 0x1fc220. The function then calls the function 0x28c788 to make
the thread of the engine.

The function 0x1fc128 has 4 arguments. The first argument is the object of
the engine. The function checks the word at 0x1fc218. The function does
nothing when the word is not 0.

The class of the engine is `ePresentationEngine` at the image 0x1fc224.

The table of the modules is in the resource section. The code of the image
does not have a reference to the table. The engine reads the table through
the system of the resources.

## The limits of the research

| The limit | The result |
|---|---|
| The names of the methods of the modules | The table gives the address of each method. The name of each method is not in the image. The research did not find the name of any method of a module. |
| The order of the methods | The table gives the methods in the order of the interface of the module. The research did not find the name of the interface of each slot. |
| The code that reads the table | The table is in the resource section. The research did not find the function that reads the table. The research found the table by its magic. |
| The module `OpenGLES` | The module has 179 methods. The research did not analyse the methods. The methods are the drawing of the screen. |

## The sources

- The image of the osos: `~/Library/Application Support/iPodFirm/re/osos-1.3.bin`
- The decompiler: Ghidra 12.1.4, with the script `DecompileAt.java` of the folder [ghidra-scripts](ghidra-scripts)
- The note of the user interface: [firmware-ui.md](firmware-ui.md)
