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
key is bound to the identity of the iPod. The research of the emulator
measured that the key binds to the 8-byte FireWire GUID in the `sysinfo_t`
block. The block is in the NOR flash. The block is not in the file
`iPod_Control/Device/SysInfo` of the volume. The app cannot make this file
for another iPod. The app can only copy this file from an iPod that has the
key.

The keys of the purchases are in the file `SC Info.sidb` of the computer with
iTunes. This file is encrypted with a key that comes from the hardware of that
computer. The app on macOS cannot read this file.

The app must copy the game files and the key file to the iPod. The app must
not make a key. The app must not copy the game files to the repository.

The program of iTunes for macOS has the code that writes the file
`IC-Info.sidb` to the iPod. The function at 0x100a05005 writes the file. The
function at 0x1006f588f makes the two paths of the files of the keys. The
program uses the names of the folders of the games with a capital letter. The
firmware uses the names with small letters.

## The game files of the owner

The owner has two folders with game files.

| Folder | Content | Size |
|---|---|---|
| `iPod Videos (5G and 5.5G only)` | 7 games. The `PlatformID` is 1. These games run on the iPod Video. | 226,585,496 bytes |
| `All iPods` | 49 games. The `PlatformID` is 123 or 1234. These games run on other iPods. | 3,053,965,978 bytes |

The `PlatformID` and the `PlatformVersion` in the manifest select the iPod. The
iPod Video accepts the games with the `PlatformID` 1 only. The games with the
`PlatformID` 123 or 1234 do not run on the iPod Video.

The games of the owner for the iPod Video are these.

| Folder | Name | Size | Executable |
|---|---|---|---|
| 11002 | iQuiz | 32,137,927 bytes | `Executables/TWA_1_1_2902110.bin` |
| 12345 | Vortex | 31,454,730 bytes | `Executables/vortex_1_1_2563290.bin` |
| 12346 | Vortex Demo | 31,542,553 bytes | `Executables/vortexTrial_1_1_2759749.bin` |
| 14005 | Ms. PAC-MAN Demo | 6,901,567 bytes | `Executables/mspacman_demo_1_1_2906666.bin` |
| 1B200 | LOST | 44,679,334 bytes | `Executables/Lost_1_1_2917525.bin` |
| 1C300 | musika | 19,912,859 bytes | `Executables/molly_1_1_3028618.bin` |
| 50514 | Royal Solitaire | 59,948,330 bytes | `Executables/Solitaire_1_1_2703086.bin` |

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
The research measured the file of the game `11002`. The table gives the size
of each atom. The size includes the 8 bytes of the header of the atom.

| Atom | Size | Content |
|---|---|---|
| `sinf` | 1032 | The whole file. |
| `frma` | 12 | The name of the program. It is `game` in 73 of the 116 files. It is 4 zero bytes in the other 43 files. |
| `schm` | 20 | The scheme `itun`. All 116 files of the owner have this scheme. |
| `schi` | 856 | The child atoms. |
| `user` | 12 | The user ID. It is (account 1) in all 7 games of the iPod Video. |
| `key ` | 12 | The size of the key. It is 4 in all the files. |
| `iviv` | 24 | The initialisation vector. It is the same in all 7 games of the iPod Video. |
| `righ` | 80 | The rights of the game. It holds the fields `veID`, `plat`, `aver`, `tran` and `medi`. |
| `name` | 264 | The name of the game. It is `Name A` in the game `11002`. |
| `priv` | 448 | The data of the key. It is 440 bytes of data. |

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
`FUN_0024df00` calls 0x1c2ca4 at 0x24df44. The full research of the check is
in [games-drm.md](games-drm.md).

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
   game. It has 7 steps. It counts the steps that passed at the offset 0x244.
   The step 2 is the step of the DRM. The other steps read the name of the
   folder, the list of the platforms, the state of the iPod and the files of
   the game. The full research of the check is in
   [games-drm.md](games-drm.md).
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

The test of the emulator used the name `Games_RO`. The test of the real iPod
on 21 October 2026 gave the cause. The cause is the case of the name of the
folder. The firmware asks for the name `games_RO` with small letters. The
file system of the emulator compares the names without the case. The emulator
gave the same result for the two names. The details are in
[games-real-ipod.md](games-real-ipod.md).

The machine of the owner has no file `IC-Info.sidb`. The key of the DRM is
therefore not present in the test. The real iPod of the owner also has no
file `IC-Info.sidb`. The game of the owner shows the message "This game cannot
be played." The step of the key is the only step that fails.

## The DRM of iTunes on Windows

The owner has the installer of iTunes for Windows in the folder with the games.
The file is `iTunes64Setup.exe`. The file is a PE32+ program. It holds a
cabinet with 5 files. The cabinet holds `iTunes64.msi`, `AppleSoftwareUpdate.msi`,
`AppleMobileDeviceSupport64.msi`, `Bonjour64.msi` and `SetupAdmin.exe`.

The file `iTunes64.msi` is 165,765,120 bytes. Its header gives the version
**12.10.11.2** for x64. The file holds a cabinet of 157,904,132 bytes with 963
folders and 4616 files. The cabinet is in the format MSZIP.

The names of the files of the MSI are in the string pool of the file. The names
that matter for the DRM are these.

| Name | Use |
|---|---|
| `CoreFP.dll` | The FairPlay core. The MSI names it `CoreFPFairPlay Core`. |
| `iPodService.exe` | The service that talks to the iPod. |
| `iPodService.dll` | The library of the service. |
| `iTunes.exe` | The program. |

The file `CoreFP.dll` is the library that makes and reads the keys. The file
`iPodService.exe` is the program that writes `IC-Info.sidb` to the iPod.

### Where the keys live

The keys of the purchases are not in the program of iTunes. They are in a
separate database. The database is in the folder `SC Info`. The folder is in
this place.

| System | Place |
|---|---|
| macOS | `/Users/Shared/SC Info` |
| Windows | `C:\ProgramData\Apple Computer\iTunes\SC Info` |

The folder holds the file `SC Info.sidb`. The file holds the keys. The file
`SC Info.sidd` holds the certificates. The name `IC-Info.sidb` in the osos of
the iPod has the same role. The iPod keeps a copy of the keys of the purchases
in its own folder `iPod_Control/iTunes`.

The database of the keys is encrypted. The key of the encryption is calculated
from the hardware of the computer. The project
[iTunes-Sid](https://metacpan.org/release/BILLH/iTunes-Sid-0.42) describes the
format. Its function `get_sid_key` takes the MAC address of the computer and
returns the key for AES. Its function `get_sid_iv` returns the vector. Its
function `fetch_all_user_keys` reads all the keys of the file `SC Info.sidb`.
Its function `find_veggie_for_userID` finds the rights of one account.

The key of the database therefore belongs to the computer. The database of the
keys belongs to the account. The copy of the keys on the iPod belongs to the
iPod.

### The two parts of the binding

The research gives two parts.

1. The account. The atom `user` of the file `sinf` holds the number of the
   account. The number is the same in all 7 games of the owner: (account 1).
   The file `sinf` of the game `1C300` has these atoms.

   | Atom | Size | Content |
   |---|---|---|
   | `sinf` | 1032 | The whole file. |
   | `frma` | 12 | The name of the program. |
   | `schm` | 20 | The scheme `itun`. |
   | `schi` | 856 | The child atoms. |
   | `user` | 12 | The number of the account: (account 1). |
   | `key ` | 12 | The size of the key. |
   | `iviv` | 24 | The vector of AES. It is the same in all 7 games. |
   | `righ` | 80 | The rights of the game. |
   | `name` | 264 | The name of the game. |
   | `priv` | 448 | The data of the key. |

   The project
   [vnc0/fairplay-scinfo](https://github.com/vnc0/fairplay-scinfo) describes
   the same format. It says that the atom `user` holds the number of the
   account. It has ImHex patterns for the file `sinf`.

2. The iPod. The iPod adds its own number to the key. The project
   [ipodclickwheelgamespreservationproject](https://github.com/Olsro/ipodclickwheelgamespreservationproject)
   says that the copy of the folder `iPod_Control` does not work on another
   iPod. It says that the DRM is tied to the serial number of the iPod.

   The osos of the firmware has the file `iPod_Control\Device\SysInfo` at
   0xa275c. This file holds the identity of the iPod. The function
   `FUN_001e797c` at 0x1e797c reads the key. It calls the method +0xa8 of the
   object of 0x193090 with the values 0x6055 and 0x6000. The object of 0x193090
   is the manager of the device.

### The limit of five accounts

The project documents the limit of Apple of 5 accounts on one iPod. The key of
the account is in the file `SC Info.sidb` of the computer. The iPod stores the
keys of all the accounts that made a purchase. The limit stops a user from
playing the games of 6 accounts on one iPod.

The community found a way around the limit. The user of the project found that
iTunes keeps the keys of an account when the user removes the games of the
account from the library. The user only needs to transfer one game of each
account. The iPod then has the keys of all the accounts. The user can then copy
all the game files to the iPod by hand.

This finding is important for the app. The app does not need to make a key. The
app only needs to copy the game files and the file of the keys.

### The result of the research of iTunes

The keys of the games are in the file `SC Info.sidb` of the computer with
iTunes. The file is encrypted with a key that comes from the hardware of that
computer. The app on macOS cannot read that file, because it cannot get the
key of a Windows computer without the hardware data of that computer.

The app can read the file `IC-Info.sidb` of an iPod. The firmware of the iPod
can read it, because the iPod has the key. The app can copy the file from one
iPod to another iPod. The key of the file is then the key of the first iPod,
and the games do not run on the second iPod.

## The names of the folders: the cause of the empty list

The research of iTunes for macOS gives the answer to the empty list in the
emulator. The names of the folders are in the program of iTunes. The program
uses names with capital letters. The firmware uses names with small letters.

| Name | iTunes 11.4 for macOS | Firmware 1.3 |
|---|---|---|
| The game files | `Games_RO` | `games_RO` |
| The data of the games | `GameData_RW` | `gamedata_RW` |
| The scores of the games | `GameStats_WO` | `gamestats_WO` |

The file system of the iPod is FAT. FAT keeps the case of the names. The
firmware asks for the folder `games_RO`. The test put the folder `Games_RO` on
the volume. The firmware did not find the folder. The test with the name
`games_RO` gave the same empty list, because the test of the names was not
complete at that time.

CAUTION: The test with the name `games_RO` gave the same result. The cause of
the empty list is therefore not known for certain. The next test must check
both names in one run and must read the state of the object of the games at
0x108711d4 again.

## The research of iTunes for macOS

The owner has installed iTunes 11.4 for macOS with Retroactive. The program is
in `/Applications/iTunes.app`. The program is a Mach-O file with two slices:
i386 and x86_64. The slice for x86_64 is 28,227,312 bytes.

The program has the library `CoreFP.framework`. The library in the program is
a Mach-O file with two slices. It is 27,883,520 bytes. The names of its
functions are obfuscated. It has 6 exported names. The names have no meaning.
The library `CoreFP.icxs` is 5,219,472 bytes. The file `CoreFP.icxs` holds the
certificates of FairPlay. The string `Apple FairPlay AAA Certification
Authority` is in it.

The program does not use the library of its own folder. The string
`/System/Library/PrivateFrameworks/CoreFP.framework/CoreFP` is in the program.
The program uses the library of the system.

The program of iTunes has the strings of the games and of the keys. The
research gives the address of each string in the slice for x86_64. The address
of the string is the address in the file. The file starts at the address
0x100000000 in the memory of the process.

| Address in the file | String | Use |
|---|---|---|
| 0x1355d0e | `Games_RO` | The folder of the game files. |
| 0x1355d17 | `GameData_RW` | The folder of the data of the games. |
| 0x1355d23 | `GameStats_WO` | The folder of the scores of the games. |
| 0x135c37d | `%@.ipg` | The name of a file of a game. |
| 0x135c3c3 | `IC-Info.sidb` | The file of the keys on the iPod. |
| 0x135c3d0 | `IC-Info.sidd` | The file of the certificates on the iPod. |
| 0x13471a9 | `iPod Games` | The name of the store of the games. |
| 0x1347e8e | `IC-Info.sidl` | The file of the list of the purchases. |
| 0x1347efa | `IC-Info.sidr` | The file of the response of the restore. |
| 0x13688cb | `IC-Info.sidv` | The file of the version of the keys. |
| 0x1342e98 | `SC Info` | The folder of the keys on the computer. |
| 0x1342ea5 | `SC Info` | The folder of the keys on the computer. |

The program has more strings for the games.

| Address in the file | String | Use |
|---|---|---|
| 0x13446ce | `itunes-games` | The name of a preference. |
| 0x13471b4 | `ContentsGameDB.xml` | The list of the games of the store. |
| 0x1347c8b | `Games Platform ID` | The name of a key of the device information. |
| 0x1347c9d | `Games Platform Version` | The name of a key of the device information. |
| 0x1347fcc | `iTunesGameIDs` | The list of the games of the library. |
| 0x13482d2 | `iPodGameIDs` | The list of the games of the iPod. |
| 0x1355a8e | `supportsGames` | The name of a key of the device information. |
| 0x1355c50 | `totalGames` | The number of the games. |
| 0x1355c5b | `totalGameBytes` | The size of the games. |

The program has the names of the DRM.

| Name | Use |
|---|---|
| `DRMUserID` | The number of the account of the key. |
| `DRMKeyID` | The number of the key. |
| `DRMFamilyID` | The number of the family of the key. |
| `DRMUserName` | The name of the account. |
| `DRMDownloaderUserID` | The number of the account of the download. |
| `DRMVersions` | The versions of the DRM. |
| `FairPlayGUID` | The number of the FairPlay key. |
| `FairPlayContext` | The context of the FairPlay key. |
| `FairPlayCertificate` | The certificate of the FairPlay key. |
| `FairPlayDeviceType` | The type of the device of the key. |
| `drm-user-id` | The name of a key of the device information. |
| `drm-key-id-1`, `drm-key-id-2` | The names of the keys of the device information. |
| `drm-platform` | The name of a key of the device information. |
| `drm-versions` | The name of a key of the device information. |

The class `IPodGamesPrefsHandler` holds the preferences of the games. The
library `iTunesLibrary.framework` has the strings `fairplay:sData` and
`fairplay:sinf`. The library `AirTrafficHost.framework` has the certificate
`Apple FairPlay AAA Certification Authority`.

### The code of the games

The program has a function that builds the path of a folder. The function has
a switch on a code of four letters. The code tells the kind of the folder. The
function calls another function with the code and the name of the folder.

| Address in the memory of the process | Code | The name of the folder |
|---|---|---|
| 0x1005d4b8a | `ltrc` | `Games_RO` |
| 0x1005d4bf5 | `ltrc` | `GameData_RW` |
| 0x1005d4c2d | `ltrc` | `GameStats_WO` |
| 0x1005d551b | `ltrc` | `Games_RO` |
| 0x1005d5567 | `ltrc` | `GameStats_WO` |

The other codes of the switch are `dmag`, `emag`, `smag`, `mcil`, `ncil`,
`muti` and `nuti`. The code `ltrc` is the code of the files of the library.
The function at 0x1005d454e and the function at 0x1005d5134 build the path.

### The code of the key file

The program has the names of the key file of the iPod. The code uses them in
several places. Each place is in a function. The table gives the address of the
name and the address of the function that uses it.

| Address of the name | The name | The address of the function | The work of the function |
|---|---|---|---|
| 0x1006f5af8 | `IC-Info.sidb` | 0x1006f588f | The file of the keys and the file of the certificates. It makes the two paths and copies the two names into them. |
| 0x1006f5b40 | `IC-Info.sidd` | 0x1006f588f | The same function. |
| 0x1006f6694 | `IC-Info.sidb` | 0x1006f6614 | Reads the file of the keys of the iPod. |
| 0x1006f6873 | `IC-Info.sidb` | 0x1006f67e8 | Reads the file of the keys and the file of the certificates. |
| 0x1006f69c8 | `IC-Info.sidb` | 0x1006f67e8 | The same function. |
| 0x1006f69fa | `IC-Info.sidd` | 0x1006f67e8 | The same function. |
| 0x100a05256 | `IC-Info.sidb` | 0x100a05005 | Writes the file of the keys to the iPod. |
| 0x100268098 | `SC Info.sidb` | 0x100267f00 | Makes the path of the file of the keys of the computer. |
| 0x10059dfdb | `IC-Info.sidl` | 0x10059d70a | Reads the file of the list of the purchases. |
| 0x10059e3e6 | `IC-Info.sidr` | 0x10059d70a | The same function. |
| 0x1005b1600 | `IC-Info.sidl` | 0x1005b1425 | Writes the file of the list of the purchases. |
| 0x1005b15c7 | `IC-Info.sidr` | 0x1005b1425 | The same function. |

The function at 0x1006f5d08 builds the path of the file. The function at
0x100ec0a00 writes the file. The function at 0x1006f5c28 and the function at
0x1006f5ca9 are in the function that makes the two paths.

The function at 0x1006f588f does this.

1. It calls 0x100268004 and 0x10026800d. These functions make an object.
2. It calls 0x100003184 and 0x10003a355. These functions make the path of
   the folder of the iPod.
3. It calls 0x1006f5c28. This function makes the path of the file.
4. It copies the name `IC-Info.sidb` into the path with 0x10000db7a and
   0xfa857a (`_memcpy`).
5. It copies the name `IC-Info.sidd` into the other path in the same way.

### The code of the games

The program has two functions that make the path of a folder of the games.
Each function has a switch on a code of four letters. The code tells the kind
of the folder.

| Address of the function | Address of the name | The name of the folder |
|---|---|---|
| 0x1005d454e | 0x1005d4b8a | `Games_RO` |
| 0x1005d454e | 0x1005d4bf5 | `GameData_RW` |
| 0x1005d454e | 0x1005d4c2d | `GameStats_WO` |
| 0x1005d4f7d | 0x1005d551b | `Games_RO` |
| 0x1005d4f7d | 0x1005d5567 | `GameData_RW` |
| 0x1005d4f7d | 0x1005d558f | `GameStats_WO` |

The other codes of the switch are `dmag`, `emag`, `smag`, `mcil`, `ncil`,
`muti` and `nuti`. The code `ltrc` is the code of the files of the library.
The function at 0x1005d454e and the function at 0x1005d5134 build the path.

The program has the list of the games of the library and the list of the games
of the iPod.

| Address of the name | The name | The address of the function |
|---|---|---|
| 0x1005a8ad4 | `iTunesGameIDs` | 0x1005a7985 |
| 0x1005b0736 | `iTunesGameIDs` | 0x1005b033f |

### The library `CoreFP.framework` of the system

The system has the library `CoreFP.framework` in the folder
`/System/Library/PrivateFrameworks/CoreFP.framework`. The file is 94,842,464
bytes. It has 3 slices: x86_64, arm64e and arm64e.x1. The file
`fairplayd` in the same folder is 37,689,264 bytes.

The file `CoreFP.tbd` in the SDK gives the version and the names of the
functions. The version is 6.8.1. The names are the same 8 names in every
slice.

| Name | The address in the slice for x86_64 | The address in the slice for arm64e |
|---|---|---|
| `_WIn9UJ86JKdV4dM` | 0x1326110 | 0xb814 |
| `_X46O5IeS` | 0x1308f40 | 0xba74 |
| `_YlCJ3lg` | 0x133f150 | 0xbf48 |
| `_dku592fbFAj` | 0x142dd00 | 0xd568 |
| `_fdjkDSAFjklaf2s` | 0x13a4d00 | 0xc6b0 |
| `_lxpgvVMLd0S7uRl` | 0x1334bd0 | 0xd368 |
| `_uvbOOqb28APZ` | 0x12eeee0 | 0xc8c0 |
| `_wnnzAiOPdQe2` | 0x1329990 | 0xcb4c |

The library in the program of iTunes has only 6 of these names. The library of
the system has 8. The names `_uvbOOqb28APZ` and `_wnnzAiOPdQe2` are new.

The 8 functions have the same first instructions. Each one has the same
prologue. The prologue sets up a frame of 0x1010 bytes and calls the same
function. The bodies are different. The code of the bodies is made hard to
read. The research did not find the names of the files of the keys in the
library. The library has no string of `SC Info` and no string of `IC-Info`.
The library has the classes of the receipts of the purchases.

| Class | Use |
|---|---|
| `FP_asn1ReceiptToken` | A receipt of a purchase. |
| `FP_asn1Token` | The base of the tokens. |
| `FP_asn1IntegerToken` | A number in a receipt. |
| `FP_asn1OSToken` | A string in a receipt. |
| `FP_asn1SequenceToken` | A list in a receipt. |
| `FP_asn1SetToken` | A set in a receipt. |
| `FP_ISPurchaseReceipt` | The receipt of a purchase of a game or of a song. |

The library has the methods `getAdamID`, `getBundleID`, `getReceiptPath`,
`getReceiptType`, `getOpaqueDSIDBuffer`, `isVPPLicensed` and `isRevoked`.
The method `isVPPLicensed` tells if the purchase has a key.

> The app must not use the library of CoreFP to make a key. The app must not
> need the library. The app can copy the file of the keys from one iPod to
> another iPod. The library of the system has the 8 names, so the app can
> find the library at the time of the run, but the app does not need it.

### Can the app make the key file?

The answer is no. The app cannot make the key file. The key is not a file that
the app can write. The key is a value that only the device can give.

The research gives the reason in three parts.

#### The key depends on the number of the account

The atom `user` of the file `sinf` holds the number of the account. The
research measured the 116 files of the owner. The files give the numbers of 12
accounts.

| The number of the account | The number of the games |
|---|---|
| (account 1) | 31 |
| (account 2) | 11 |
| (account 3) | 3 |
| (account 4) | 2 |
| (account 5) | 2 |
| (account 6), (account 7), (account 8), (account 9), (account 10), (account 11), (account 12) | 1 each |

The games of one account have the same number. The games of different
accounts have different numbers. The number is the number of the account of the
purchase. The number is in the file `sinf` of the game. It is not a secret.

#### The key depends on the number of the iPod

The file `sinf` has an atom `priv`. The atom holds 440 bytes of data. The
research measured the data of all 116 files. Each file has its own data. There
are 116 different data blocks. The project
[FairFree](https://github.com/roothide/FairFree) says that the data of the
atom `priv` is the copy of the first part of the file `sinf`, and that the copy
is encrypted with a key that comes from the device.

The firmware of the iPod reads the file `sinf` of the game. The function
`FUN_000e2d30` at 0xe2d30 reads the atoms of the file. The constant at
0xe301c is `sinf`. The constant at 0xe3024 is `cpsa`, the atom `asdt`. The
function `FUN_00084f18` at 0x84f18 reads the atom `asdt`. The atom `asdt`
holds the dates of the account of the key.

The firmware has the function `FUN_001e797c` at 0x1e797c that reads the key.
It calls the method +0xa8 of the object of 0x193090 with the values 0x6055 and
0x6000. The object of 0x193090 is the manager of the device. The firmware
takes the number of the device from the manager of the device. The string
`SerialNumber` is at 0x176b24. The function `FUN_00175c74` at 0x175c74 gives
the number of the device to the computer.

The function `FUN_001c2ca4` at 0x1c2ca4 reads the key of the game. It calls
`FUN_001b0700` at 0x1c2cc0. The function `FUN_001b0700` at 0x1b0700 opens the
DRM library. The function `FUN_001b069c` at 0x1b069c reads the key of the user
ID. The function `FUN_001b08f0` at 0x1b08f0 searches the list of the keys. The
list of the keys is in the file `IC-Info.sidb` of the iPod.

The key of the game therefore depends on two things.

1. The number of the account. This number is in the file `sinf` of the game.
   The app can read it. The app cannot change it, because the file `sinf` has a
   signature.
2. The number of the iPod. The key of the game is bound to the number of the
   iPod. The app cannot know this number for an iPod that never had the key.

#### The file of the keys is unique to the iPod

The key file of the iPod holds the key of each account that made a purchase.
The key of an account in the file is the key of that account for that iPod. The
project [ipodclickwheelgamespreservationproject](https://github.com/Olsro/ipodclickwheelgamespreservationproject)
says the same. It says that the file `IC-Info.sidb` is unique to the iPod and
to its installation. It says that a copy of the file does not work on another
iPod. It says that the DRM is tied to the number of the iPod.

The research of the program of iTunes for macOS gives the same result. The
function at 0x1006f588f makes the path of the file `IC-Info.sidb` and the path
of the file `IC-Info.sidd`. The function at 0x100a05005 writes the file of the
keys to the iPod. The function reads the keys from the store of the computer.
The store of the computer has the keys of the accounts. The program does not
make a key. The program copies a key that the server of Apple gave to the
account.

> The app cannot make the key file for an iPod that never had the key. The
> app can only copy the file of the keys from an iPod that has the key. The
> app can then copy the game files. The games run on the iPod of the key.

#### What the app can do

The app can do three things. The app cannot do a fourth thing.

1. The app can read the number of the account of each game. The app can show
   this number to the user. The app can group the games of one account.
2. The app can copy the game files to the folder `games_RO` of the iPod. The
   app must use the names with small letters. The program of iTunes uses the
   names with a capital letter. The firmware uses the names with small letters.
3. The app can copy the file `IC-Info.sidb` from another iPod to the iPod. The
   file works only on the iPod of the file.
4. The app cannot make the file `IC-Info.sidb` for an iPod that never had the
   key.

### The result of the research of iTunes for macOS

The program of iTunes for macOS has the code that writes the file
`IC-Info.sidb` to the iPod. The program reads the keys from the file
`SC Info.sidb` of the computer. The program can also get the keys from the
server of Apple.

The program is for macOS. The app of the owner is for macOS. The app can use
the same code. The app does not need to know the format of the key file. The
app does not need to know the algorithm of the key. The app needs the file of
the keys of an iPod that has the key.

> The app must not ship the code of Apple. The app must not copy the program
> of Apple. The app must copy the file of the keys of the iPod, and it must
> copy the game files of the owner.

The research of the 8 functions of the library `CoreFP.framework` is not
needed for the app. The app copies the file. The research is only for the
knowledge of the format of the key file.

## The open questions

- The bit of the games in the main menu mask. The function `FUN_00105a04` at
  0x105a04 gives the bit of a menu item.
- The check of the digest of the executable. The function `FUN_0024df00` at
  0x24df00 checks it. The app must know if the check uses the digest of the
  manifest or the signature of the file.
- The list of the folders that the firmware makes on the iPod. The names are
  `gamedata_RW`, `gamestats_WO` and `gamedata_ShareRW` in the firmware, and
  `GameData_RW` and `GameStats_WO` in iTunes.
- The state 5 and 6 of the class. The firmware runs a game in these states.
- The function that reads the file `IC-Info.sidb` in the firmware. The names
  are at 0x69f6fc and 0x69f70c. The DRM library of the system of the iPod
  reads the file. The research found no code in the osos that opens the file.
- The function that decrypts the program of a game. The research of the check
  of the DRM is in [games-drm.md](games-drm.md). The osos has no cipher for
  the program of a game. The decryption is in the DRM library of the system.
  The library is outside the osos. The research must use the emulator.
- The way that the key is bound to the identity of the iPod. The research of
  the emulator measured that the key binds to the 8-byte FireWire GUID in the
  `sysinfo_t` block. The block is in the NOR flash. The string
  `SerialNumber` is at 0x176b24. The function `FUN_00175c74` at 0x175c74 gives
  the number of the iPod to the computer. The code that uses the number for
  the key is not found yet.
- The six functions of the library `CoreFP.framework` in the program of iTunes.
  The names are obfuscated. The app does not need them. The research is only
  for the knowledge of the format of the key file.
- The code of `iPodService.exe` and `CoreFP.dll` in iTunes 12.10.11.2 for
  Windows. The files are in the cabinet of the MSI. The next step is to
  extract them and to find the function that writes the file `IC-Info.sidb` to
  the iPod.

## The sources of the research

| Source | Use |
|---|---|
| [ipodclickwheelgamespreservationproject](https://github.com/Olsro/ipodclickwheelgamespreservationproject) | The method of the community. The key file on the iPod, the limit of 5 accounts, the way around the limit, the name of the folders of the games. |
| [vnc0/fairplay-scinfo](https://github.com/vnc0/fairplay-scinfo) | The format of the file `sinf`. It says that the atom `user` holds the number of the account. It has ImHex patterns. |
| [iTunes-Sid](https://metacpan.org/release/BILLH/iTunes-Sid-0.42) | The format of the file `SC Info.sidb`. The key of the database comes from the MAC address of the computer. |
| [roothide/FairFree](https://github.com/roothide/FairFree) | The study of the atom `priv` of the file `sinf` and of the daemon `fairplayd`. It is for iOS. It is not for the iPod Video. |
| [The night water article](https://www.nightwater.email/ipod-games/) | The story of the project. It says that a user can hold many accounts in one iTunes. |
| [Apple's page of the games](https://github.com/Olsro/ipodclickwheelgamespreservationproject#preservation-status-for-each-game) | The list of the 54 games and the number of each game. |

The sources are on the internet. The project keeps no copy of them. The owner
reads them there.
