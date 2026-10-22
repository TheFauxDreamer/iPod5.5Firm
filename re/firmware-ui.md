# The user interface of RetailOS 1.3

This note gives the research of the system "The user interface" of the note
[firmware-systems.md](firmware-systems.md). The system has 2 named parts. The
parts are the names `SearchHelperThread` and `WindowManager`.

The note gives the resources of the user interface, the classes of the screens,
the elements of a screen, the tables of the classes and the registry of the
modules.

The addresses are the offsets in the image of the osos. The CPU address of the
code is the offset plus 0x10000000. The note uses the offset.

> This note is the research of the decompilation project. The notes of the
> earlier research stay as they are. The note [cover-flow.md](cover-flow.md) and
> the note [list-rendering.md](list-rendering.md) give the Cover Flow and the
> list. The note [album-art-v2.md](album-art-v2.md) gives the covers of the
> albums. This note gives the system of the user interface as a whole.

## The summary

The user interface of the iPod is not in the code. The screens, the texts, the
pictures and the menus are in the **resources** of the image `osos`. The code
holds the classes that read the resources and draw them.

The image has 25 blocks of the resources. The block 24 is the **main block**. The
other 24 blocks hold the texts of the 24 languages. The main block has 8
sections.

| The section | The number | The content |
|---|---|---|
| `BMap` | 403 | The pictures of the screens. |
| `Str ` | 991 | The texts of the screens. |
| `View` | 619 | The screens. Each screen has a list of elements. |
| `Type` | 158 | The class of each screen. |
| `Menu` | 40 | The menus. |
| `Bits` | 1 | The small pictures. |
| `LDTm` | 1 | The load times. |
| `TCmd` | 1 | The table of the commands. |

The main block starts at the image 0x331da0. The table of the `Type` section
is at 0x336188. The table of the `View` section is at 0x3368f0. The table of the
`Menu` section is at 0x333128. The table of the `Str ` section is at 0x333308.
The table of the `BMap` section is at 0x331e2c.

The other 24 blocks have the sections `LDTm`, `Str ` and sometimes `Type` and
`View`. The block 0 is at 0x2aadfc. The block 23 is at 0x32b85c. Each block has
890 texts, or 60 for the 4 blocks of the languages with few texts.

## The registry of the resources

The code reads the resources with a **module registry**. The registry is a list
of objects. Each object has a name. The method at the slot +0x5c of the object
looks up a name in the list.

| The function | The work |
|---|---|
| 0x21f3dc | Looks up a name in the registry. The function walks the list of the objects. |
| 0x21f254 | Looks up a name in the list of the children of an object. |
| 0x21a168 | Registers a class. The function looks up the class of a type and puts it in the object. |

The names of the modules of the screen are in the strings of the image.
`OpenGLES` is at 0x7947c, `Filesytem` at 0x7978c, `Metadata` at 0x79918,
`InputEvents` at 0x79c44, `Settings` at 0x79c90 and `AsyncFileIO` at 0x79bbc.

The function 0x1fc128 makes the object of the engine of the screen. The
function calls the function 0x22463c with the name "ImagePresentationEngine" at
0x1fc220. The function 0x28c788 makes the thread of the engine.

## The class of a screen

The section `Type` has 158 resources. Each resource has 16 bytes.

| The word | The content |
|---|---|
| +0x00 | The offset of the table of the class of the screen. |
| +0x04 | The number of the elements of the screen. |
| +0x08 | The colour of the screen. The bytes are the red, the green, the blue and the alpha. 131 of the 158 types have the colour 0x000000ff. |
| +0x0c | The flags of the screen. The values are 0, 1, 256, 257, 512 and 513. |

The offset of the table of the class is a number of 4-byte words from the base
0x653048. The function 0x168938 reads the `Type` section. The function looks up
the type by its number, then it calls the function 0x21a168 to register the
class.

The function 0x16914c makes the object of a screen of a class. The function
copies the class of the type to the object. The function calls the function
0x211bd4 and the function 0x211c04 to read the elements.

### The 19 tables of the classes of the screens

The 158 types use 19 tables. The tables are in the region 0x66a904 to 0x66a958.
The tables overlap. A table of a derived class starts with the methods of the
class of the base.

| The table | The slots | The types | The methods |
|---|---|---|---|
| 0x66a904 | 11 | 39 | 0x16c650, 0x16c638, 0x252c10, 0x16c610, 0x16c618, 0x25ab68, 0x25ab68, 0x16c614, 0x25ab68, 0x25ab68, 0x252ba8 |
| 0x66a908 | 10 | 2 | the table 0x66a904 without the first method |
| 0x66a90c | 9 | 3 | the table 0x66a904 without the first 2 methods |
| 0x66a910 | 8 | 3 | the table 0x66a904 without the first 3 methods |
| 0x66a914 | 7 | 3 | the table 0x66a904 without the first 4 methods |
| 0x66a918 | 6 | 3 | the table 0x66a904 without the first 5 methods |
| 0x66a91c | 5 | 3 | the table 0x66a904 without the first 6 methods |
| 0x66a920 | 4 | 16 | 0x16c614, 0x25ab68, 0x25ab68, 0x252ba8 |
| 0x66a924 | 3 | 6 | 0x25ab68, 0x25ab68, 0x252ba8 |
| 0x66a928 | 2 | 6 | 0x25ab68, 0x252ba8 |
| 0x66a92c | 1 | 4 | 0x252ba8 |
| 0x66a930 | 0 | 2 | no method |
| 0x66a934 | 0 | 2 | no method |
| 0x66a938 | 8 | 57 | 0x16cbc8, 0x16cbb0, 0x222de4, 0x222de8, 0x252c18, 0x16c6b4, 0x24f708, 0x24f720 |
| 0x66a940 | 6 | 3 | the table 0x66a938 without the first 2 methods |
| 0x66a944 | 5 | 2 | the table 0x66a938 without the first 3 methods |
| 0x66a948 | 4 | 2 | the table 0x66a938 without the first 4 methods |
| 0x66a94c | 3 | 1 | the table 0x66a938 without the first 5 methods |
| 0x66a950 | 2 | 1 | the table 0x66a938 without the first 6 methods |

The methods 0x222de4 and 0x222de8 are the destructor and the method of the
class. The method 0x252ba8 is the method of the class of the screen that has no
screen of its own.

> The research did not find the name of each of the 19 classes. The names of the
> classes of the screens are not in the strings of the image. The constructor of
> the class of the table 0x66a904 is at 0x16c61c. The constructor of the class
> of the table 0x66a938 is at 0x16cb88.

## The elements of a screen

The section `View` has 619 resources. The header of a screen has 16 bytes.

| The word | The content |
|---|---|
| +0x00 | The number of the elements. |
| +0x04 | The offset of the elements from the end of the header. |
| +0x08 | The flags of the screen. |
| +0x0c | The tag of the kind of the element. |

The tag is 4 bytes. The tag says the kind of the element.

| The tag | The kind | The number | The reader |
|---|---|---|---|
| `enoN` | the empty element | 366 | 0x141184 |
| ` rtS` | the text | 144 | 0xa6bd0 |
| `paMB` | the picture | 86 | 0xab7f0 |
| `warD` | the drawing | 13 | 0x12f150 |
| `ltnC` | the control | 6 | 0x16c080 |
| `tStS` | the state of the text | 3 | — |
| `mTtD` | the title | 1 | 0x10d278 |

The tags are in the strings of the image. `enoN` is at 0x1411fc, `paMB` at
0xab8a4, ` rtS` at 0xa6d28, `warD` at 0x12f1a0, `ltnC` at 0x16c0e8 and
`mTtD` at 0x10d2b0.

Each reader makes the object of the element. The class of the element of the
tag `enoN` has the table at 0x668250. The table has 8 slots. The first slot is
0. The second slot is the destructor at 0x141200. The slots 2 and 3 are the
destructor and the method of the class at 0x222de4 and 0x222de8.

The function 0x141060 makes the object of the empty element. The function calls
the function 0x141184. The function 0x141184 makes the object of 0x80 bytes.
The function reads the class of the element and calls the function 0x149e64
twice. The function 0x149e64 makes a small structure of 4 words. The function
calls the function 0x21f254 to find the name of the text of the element.

## The class of the control

The function 0x16c080 reads the element of the tag `ltnC`. The function makes
the object of the control. The class of the control has a table.

The function 0x16c328 is the method of the class of the control. The function
reads the type of the control at +4 of the object.

| The type | The work |
|---|---|
| 9 | The function calls the function 0x16bd34. |
| 0x19 | The function reads the object at +0xa80 and calls the function 0x16c0f4. |
| other | The function calls the function 0x16a128. |

The function 0x16bd34 is the method of the type 9. The function calls the
function 0x9bb30 and the function 0x16bedc.

## The menus

The section `Menu` has 40 resources. The header of a menu has 12 bytes.

| The word | The content |
|---|---|
| +0x00 | The number of the items of the menu. |
| +0x04 | The offset of the items from the end of the header. The value is 36. |
| +0x08 | The offset of the items again. The value is 36. |

The menu 24094 is the main menu. The menu 24440 is the menu of the music. The
menu 24598 is the menu of the settings. The menu 24600 is the menu of the main
menu in the settings. The menu 24604 is the menu of the daylights.

The numbers of the items of the menus are in the resources of the `Str `
section.

## The tasks of the system

The system has 2 tasks. The table of the tasks of the firmware is at 0x25d63c.
The 2 tasks are not in that table.

| The task | The name | The work |
|---|---|---|
| `WindowManager` | 0x170c5c | The windows of the screen. |
| `SearchHelperThread` | 0x155ed0 | The help of the search. |

The task `WindowManager` is made by the function 0x170bc8. The function calls
the function 0x11c808 with the name "WindowManager" at 0x170c5c. The size of
the stack is 0x10. The task is made at the run time.

The task `SearchHelperThread` is made by the function 0x155e7c. The function
calls the function 0x11c808 with the name "SearchHelperThread" at 0x155ed0.
The size of the stack is 0 and the number of the events is 0x32.

## The class of the engine of the screen

The class of the engine of the screen is `ePresentationEngine`. The name is at
the image 0x1fc224. The function 0x1fc128 makes the object of the engine.

The class of the application has a table with 17 slots at 0x676aec. The
constructor of the class is at 0x22846c. The note
[../docs/firmware-functions.md](../docs/firmware-functions.md) gives the table
of the application object at 0x66a510.

## The limits of the research

| The limit | The result |
|---|---|
| The names of the 19 classes of the screens | The names of the classes of the screens are not in the strings of the image. The research gives the tables of the classes and the number of the types of each table. |
| The name of each type | The research did not find the name of each of the 158 types. The types are named by their number. |
| The elements of a screen | The research found the header of a screen and the 7 kinds of the elements. The research did not decode the layout of the elements. |
| The menus | The research found the header of a menu and the numbers of the menus. The research did not decode the items of a menu. |
| The 158 `Type` resources | The research found the table of the class of each type. The research did not find the meaning of the number of the elements and of the flags. |
| The names of the modules of the screen | The research found the 6 names of the modules in the strings. The research did not find the table of the modules. |
| The list and the menu | The note [list-rendering.md](list-rendering.md) has the list. The note [cover-flow.md](cover-flow.md) has the Cover Flow. The research did not trace the code of the list. |

## The sources

- The image of the osos: `~/Library/Application Support/iPodFirm/re/osos-1.3.bin`
- The decompiler: Ghidra 12.1.4, with the script `DecompileAt.java` of the folder [ghidra-scripts](ghidra-scripts)
- The module of the resources of the project: [../src/ipodfw/resources.py](../src/ipodfw/resources.py)
- The note of the Cover Flow: [cover-flow.md](cover-flow.md)
- The note of the list: [list-rendering.md](list-rendering.md)
