# iPod Games

This note describes how the iPod Video with RetailOS 1.3 finds and runs iPod
Games. The research uses Ghidra 12.1.4 on the osos image of firmware 1.3. It
uses the game files of the owner in the folder `~/Downloads/iPod Games Files`.

The goal is to add games to an iPod. The iPod cannot receive games from iTunes
any more, because iTunes does not run on macOS. The iPodFirm app must copy the
game files to the iPod instead.

The game files use a DRM. The DRM is the reason that the app cannot add the
games without a key. This note describes the DRM. It gives the result that the
owner must decide.

## The result in short

The firmware reads the games from the folder `iPod_Control/games_RO`. It reads
the `Manifest.plist` file of each game first. It checks the `PlatformID` and
the `PlatformVersion` of the manifest. It then checks the files of the game
against the `Files` array of the manifest. It then reads the DRM key of the
game.

The DRM key is in the file `iPod_Control/iTunes/IC-Info.sidb` of the iPod. The
key is bound to the serial number of the iPod. The app cannot make this file
for another iPod. The app can only copy this file from an iPod that has the
key.

The app must copy the game files and the key file to the iPod. The app must
not make a key. The app must not copy the game files to the repository.

## The game files of the owner

The owner has two folders with game files.

| Folder | Content | Size |
|---|---|---|
| `iPod Videos (5G and 5.5G only)` | 7 games. The `PlatformID` is 1. These games run on the iPod Video. | 218 MB |
| `All iPods` | 44 games. The `PlatformID` is 123 or 1234. These games run on other iPods. | 2.9 GB |

The `PlatformID` and the `PlatformVersion` in the manifest select the iPod. The
iPod Video accepts the games with the `PlatformID` 1 only. The games with the
`PlatformID` 123 or 1234 do not run on the iPod Video.

The games of the owner for the iPod Video are these.

| Folder | Name | Size | Executable |
|---|---|---|---|
| 11002 | iQuiz | 31 MB | `Executables/TWA_1_1_2902110.bin` |
| 12345 | Vortex | 30 MB | `Executables/vortex_1_1_2563290.bin` |
| 12346 | Vortex Demo | 30 MB | `Executables/vortexTrial_1_1_2759749.bin` |
| 14005 | Ms. PAC-MAN Demo | 6.7 MB | `Executables/mspacman_demo_1_1_2906666.bin` |
| 1B200 | LOST | 43 MB | `Executables/Lost_1_1_2917525.bin` |
| 1C300 | musika | 19 MB | `Executables/molly_1_1_3028618.bin` |
| 50514 | Royal Solitaire | 57 MB | `Executables/Solitaire_1_1_2703086.bin` |

The folder name of a game is the GUID of the game. The GUID is the same as the
name of the folder.

## The folders on the iPod

The firmware uses four folders in `iPod_Control`. The names are in the osos at
0x2a9c3c. The names are in small letters. The project
[ipodclickwheelgamespreservationproject](https://github.com/Olsro/ipodclickwheelgamespreservationproject)
uses the names `GameData_RW` and `GameStats_WO`. The osos of firmware 1.3 has
only the small letter names.

| Address | Name | Use |
|---|---|---|
| 0x2a9c3c | `games_RO` | The game files. The firmware only reads this folder. |
| 0x2a9c48 | `gamedata_RW` | The data of the games. The firmware reads and writes this folder. |
| 0x2a9c54 | `gamestats_WO` | The scores of the games. The firmware writes this folder. |
| 0x2a9c64 | `gamedata_ShareRW` | The data of the games for the shared mode. |

The function `FUN_000d9d30` at 0xd9d30 returns the name of a folder. The
argument selects the folder. The argument 0 gives `games_RO`, 1 gives
`gamedata_RW`, 2 gives `gamestats_WO` and 3 gives `gamedata_ShareRW`.

The function `FUN_000deff4` at 0xdeff4 builds the full path of a folder. It
uses the format `iPod_Control/%s/%s%s%s` at 0xdf0a8. The argument 3 of the
function gives the other format `iPod_Control/%s%s%s` at 0xdf094. This format
has no directory between `iPod_Control` and the name of the folder.

The function `FUN_000deff4` calls `FUN_00223cbc` with the path and the name of
the folder. This function makes the path.

The path of the games is `iPod_Control/games_RO/`. The string is at 0x6788bb.
The path of the manifest of a game is `iPod_Control/games_RO/<GUID>/Manifest.plist`.
The firmware builds this path with the format at 0xdf0a8.

## The manifest of a game

Each game has a folder in `games_RO`. The name of the folder is the GUID of the
game. The folder has a `Manifest.plist` file. The firmware reads this file
first. It does not read the other files of the game before this step.

The keys of the manifest are in the osos at 0x678d49. The firmware uses these
keys.

| Address | Key | Use |
|---|---|---|
| 0x678d49 | `GUID` | The ID of the game. It is the name of the folder. |
| 0x678d4e | `BuildID` | The build of the game. |
| 0x678d56 | `PlatformID` | The iPod that runs the game. |
| 0x678d97 | `PlatformVersion` | The version of the platform. |
| 0x678d6e | `ExecutablePath` | The file with the program of the game. |
| 0x678d7d | `LaunchingArtwork` | The picture of the game. |
| 0x678da7 | `BuildIdentifier` | The build of the game. |
| 0x678db7 | `Files` | The list of the files of the game. Each file has a `Digest`, a `Path` and a `Size`. |
| 0x678dcc | `Platforms` | The list of the platforms. Each platform has a `BuildID`, an `ExecutablePath`, a `LaunchingArtwork`, a `PlatformID`, a `PlatformVersion` and a `Size`. |

The string `Manifest.plist.p7b` is at 0x678ddd. The string `.sinf` is at
0x678df0. The firmware uses them to check the signature of the game.

The string `iPod_Control/games_RO/` is at 0x6788bb. The string
`Manifest.plist` is at 0x6788d2. Both are in the data area. The code that uses
them is at 0x24e240.

## The DRM of the games

The program of each game uses a FairPlay DRM. The program file has high
entropy. It is not ARM code. The file `Manifest.plist` and the file
`iTunesMetaData` of the game are plain text. The program file is not.

Each game has a file with the name of the program and the suffix `.sinf`. The
file holds the FairPlay atoms. The file of the game `1C300` has these atoms.

| Atom | Size | Content |
|---|---|---|
| `sinf` | 1032 | The whole file. |
| `frma` | 12 | The name of the program. |
| `schm` | 20 | The scheme `itun`. |
| `schi` | 856 | The child atoms. |
| `user` | 0x0c | The user ID. It is (account 1) in all 7 games. |
| `key ` | 12 | The size of the key. |
| `iviv` | 24 | The initialisation vector. It is the same in all 7 games. |
| `name` | 264 | The name of the game. |

The user ID is the same in all 7 games of the owner. The initialisation vector
is the same in all 7 games. The key is not in the `sinf` file. The key is in
the file `IC-Info.sidb` of the iPod.

The firmware has the two names of the key file in the osos.

| Address | Name | Use |
|---|---|---|
| 0x69f6fc | `IC-Info.sidd` | The data of the key file. |
| 0x69f70c | `IC-Info.sidb` | The key file. |

The key file is in the folder `iPod_Control/iTunes/`. The firmware builds this
path with the string `iPod_Control\iTunes\` at 0xb4de0, 0xbc074, 0xf383c and
0xf5384. The functions that use this path are 0xb4a64, 0xbbf2c, 0xf3794 and
0xf52b8.

The function `FUN_001e797c` at 0x1e797c reads the key. It calls the method
+0xa8 of the object of 0x193090 with the values 0x6055 and 0x6000. The
function `FUN_001c2b78` at 0x1c2b78 calls this function. The function
`FUN_0024df00` at 0x24df00 calls 0x1c2b78 at 0x24df24. The function
`FUN_001c2ca4` at 0x1c2ca4 reads the key of the game. The function
`FUN_0024df00` calls 0x1c2ca4 at 0x24df44.

The function `FUN_001c2ca4` opens the key store with `FUN_001b0700` at
0x1c2cc0. The function `FUN_001b0700` at 0x1b0700 opens the DRM library. The
function `FUN_001b069c` at 0x1b069c reads the key of the user ID. The
function `FUN_001b08f0` at 0x1b08f0 searches the list of the keys.

The string `SerialNumber` is in the osos at 0x176b24. It is a key of the
device information. The key of the DRM is bound to this number. The project
[ipodclickwheelgamespreservationproject](https://github.com/Olsro/ipodclickwheelgamespreservationproject)
says the same. It says that a copy of the folder `iPod_Control` does not work
on another iPod.

## The code of the games

The class of the games is at 0x24d000 to 0x24f000 in the osos. The object of
this class has the fields at these offsets. The object is at 0x108711d4.

| Offset | Field | Use |
|---|---|---|
| +0x100 | state | The state of the class. The values 5 and 6 mean that a game runs. |
| +0x214 | the file list | The list of the files of the game. |
| +0x218 | the state of the scan | The state of the scan of the games folder. |
| +0x224 | the wait queue | The queue of the tasks that wait for the scan. |
| +0x230 | the state of the run | The state of the run of a game. |
| +0x231 | the state of the screen | The state of the screen of the games. |
| +0x234 | the index of the game | The number of the game in the list. |
| +0x238 | the path of the game | The path of the folder of the game. |
| +0x240 | the game | The object of the game. |
| +0x244 | the count of the errors | The number of the steps that failed. |
| +0x248 | the flag of the error | 1 means that the scan failed. |
| +0x249 | the flag of the run | 1 means that the game is installed. 2 means that the game runs. |
| +0x24c | the result | The result of the check of the game. |
| +0x250 | the function of the game | The function that the firmware calls to run the game. |
| +0x254 | the function of the end | The function that the firmware calls when the game ends. |
| +0x260 | the function of the platform | The function of the platform of the game. |
| +0x264 | the list of the platforms | The list of the platforms of the game. |
| +0x268 | the list of the games | The list of the games of the iPod. |
| +0x26c | the first game | The first game of the list. |
| +0x270 | the last game | The last game of the list. |

### The scan of the games folder

The function `FUN_0024d9f8` at 0x24d9f8 scans the folder of the games. It sets
the state of the scan to 3 at the end. It reads the list of the directories in
`games_RO`. It does not read the files of a game.

The function `FUN_0024de30` at 0x24de30 waits for the state 4. It sets the state
to 5 or 6. The function `FUN_0024dde8` at 0x24dde8 waits for the state 6 or 3.
It sets the state to 7. The function `FUN_0024db38` at 0x24db38 waits for the
state 7. It sets the state to 9. The function `FUN_0024dc24` at 0x24dc24 waits
for the state 10. It sets the state to 1. The function `FUN_0024e4b4` at
0x24e4b4 waits for the state 1. The function `FUN_0024e5d0` at 0x24e5d0 waits
for the state 3. The function `FUN_0024e1e8` at 0x24e1e8 waits for the state 1
or 10.

The function `FUN_0024dc0c` at 0x24dc0c sets the state of the scan. It accepts
the values 1 to 10.

The loop `FUN_0024e554` at 0x24e554 runs the scan. It calls the functions in
this order.

1. `FUN_0024d9f8` at 0x24d9f8. The scan of the folder.
2. `FUN_0024e66c` at 0x24e66c. The check of the game.
3. `FUN_0024de30` at 0x24de30. The wait for the state 4.
4. `FUN_0024e0dc` at 0x24e0dc. The run of the game.
5. `FUN_0024dde8` at 0x24dde8. The wait for the state 6.
6. `FUN_0024db38` at 0x24db38. The wait for the state 7.
7. `FUN_0024e64c` at 0x24e64c.
8. `FUN_0024dc24` at 0x24dc24. The wait for the state 10.

The function `FUN_0024d87c` at 0x24d87c runs the same loop in a task. The task
starts at `FUN_0024e718` at 0x24e718. The class object is at 0x108711d4. The
class makes one task for the scan.

### The check of a game

The function `FUN_0024e240` at 0x24e240 reads and checks one game. It returns 1
when the game is valid. It does these steps.

1. It builds the path of the manifest with `FUN_000deff4` at 0xdeff4. The
   argument 0 gives the folder `games_RO`. The last argument is the string
   `Manifest.plist` at 0x24e36c.
2. It reads the manifest. The function `FUN_00256610` at 0x256610 reads the
   file. The function `FUN_0011554c` at 0x11554c parses the file.
3. It calls `FUN_0024df00` at 0x24df00. This function checks the files of the
   game. It has 7 steps. It reads the list of the files, the signature, the
   `iTunesMetaData` file, the resources and the other files.
4. It calls `FUN_0024e37c` at 0x24e37c. This function checks the platform of
   the game.
5. It calls `FUN_0024e074` at 0x24e074. This function makes the list of the
   games.

The function `FUN_0024e37c` at 0x24e37c reads the `Platforms` array of the
manifest. It compares the `PlatformID` and the `PlatformVersion` of the
platform with the values of the iPod. It returns 0 when the game is valid. It
returns 0xffffff01 when the platform is not on the iPod. It returns 0xffffff02
when the platform has no executable.

The function `FUN_0024df00` at 0x24df00 checks the files of the game. It uses
the `Files` array of the manifest. Each file has a `Digest`, a `Path` and a
`Size`. The function checks the size of each file. It checks the digest of the
executable. It reads the `iTunesMetaData` file of the game. The string
`/Resources/VideoCore` at 0x678df6 is the path of the video library. The
strings `Boot` at 0x678e0b and `Library` at 0x678e10 are the folders of the
video library.

The function `FUN_0024e66c` at 0x24e66c calls the function `FUN_0024e240` at
0x24e240. It runs only when the state of the scan is 3. It starts the game
with the function `FUN_001d32e0` at 0x1d32e0.

### The list of the games

The function `FUN_0024dca0` at 0x24dca0 gives the count of the games in the
list. The count is at most 0x5b (91) games. The count is 1 in the state 3.

The function `FUN_0024dce8` at 0x24dce8 makes the list of the games. It reads
the directory of the games. It reads the name of each game. The function
`FUN_0024d918` at 0x24d918 makes one item of the list. Each item has a type
and a number.

The function `FUN_0024d7c0` at 0x24d7c0 makes the list of the games. It sets
the state of the scan to 2. It sets the index of the game to 0xffffffff.

## The screen of the games

The function `FUN_0012e3cc` at 0x12e3cc is the handler of the screen. It calls
the function `FUN_0024d88c` at 0x24d88c. This function gives the object of the
games. The function `FUN_0024d99c` at 0x24d99c starts the scan. The function
`FUN_0024e4b4` at 0x24e4b4 waits for the state 1. The function `FUN_0024e1e8`
at 0x24e1e8 waits for the state 1 or 10.

The function `FUN_0012dd80` at 0x12dd80 is the handler of the screen when it
closes.

The word `Games` is in the JavaScript of the user interface. The JavaScript is
in the resource `TCmd` 9088 at 0x4b441c. The word `Games` is at these places.

| Address | Use |
|---|---|
| 0x4b145c | The name of the menu item. |
| 0x4b38f2 | The name of the item in the menu of the settings. |
| 0x4b3b44 | The name of the item in the list of the main menu. |
| 0x4b4308 | The name of the item in the error screen. |

The words `Resume Game` at 0x4b14d8 and `Testing` at 0x4b14d0 are in the same
area.

The function `FUN_00131874` at 0x131874 reads the value of a key of the
settings. The function `FUN_001222c4` at 0x1222c4 reads a list of a key of the
settings. The function `FUN_000deff4` at 0xdeff4 makes the path of a file of
the `iPod_Control` folder.

The main menu mask is at 0x9d880. The function `FUN_00193470` at 0x193470
returns the state of a menu item. The function `FUN_00105a04` at 0x105a04 gives
the bit of a menu item. The bit for the games is not known yet.

## The test in the emulator

The test used the emulator of the project. The games of the owner were copied
to the folder `iPod_Control/Games_RO` of the volume of the emulator. The
volume is FAT32.

The result of the test is this.

- The item `Games` is in the main menu. The item opens the screen of the games.
- The list of the games is empty.
- The object of the games at 0x108711d4 is empty. All fields are 0. The
  function `FUN_0024d88c` at 0x24d88c did not make the object.
- The histogram shows that the code of the games at 0x24d000 to 0x24f000 did
  not run. The blocks that ran are at 0x24e840 to 0x24ee80. These blocks are
  the drawing of the screen. The function `FUN_0024e9c0` at 0x24e9c0 draws the
  screen of the games.

The cause of the empty list is not known yet. The two possible causes are the
name of the folder and the key of the DRM. The name of the folder in the
firmware is `games_RO` in small letters. The project
[ipodclickwheelgamespreservationproject](https://github.com/Olsro/ipodclickwheelgamespreservationproject)
uses the name `Games_RO`. The test used the name `Games_RO`. The test with the
name `games_RO` gave the same result. The list was empty in both tests.

The machine of the owner has no file `IC-Info.sidb`. The key of the DRM is
therefore not present in the test.

## The open questions

- The cause of the empty list in the emulator. The object of the games at
  0x108711d4 is empty. The function `FUN_0024d88c` at 0x24d88c did not make
  the object.
- The bit of the games in the main menu mask. The function `FUN_00105a04` at
  0x105a04 gives the bit of a menu item.
- The check of the digest of the executable. The function `FUN_0024df00` at
  0x24df00 checks it. The app must know if the check uses the digest of the
  manifest or the signature of the file.
- The list of the folders that the firmware makes on the iPod. The names are
  `gamedata_RW`, `gamestats_WO` and `gamedata_ShareRW`.
- The state 5 and 6 of the class. The firmware runs a game in these states.
- The function that reads the file `IC-Info.sidb`. The names are at 0x69f6fc
  and 0x69f70c. The code that uses them is not found yet.
- The way that the key is bound to the serial number. The string
  `SerialNumber` is at 0x176b24. The code that uses it for the key is not
  found yet.
