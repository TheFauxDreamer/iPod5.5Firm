# The systems of the firmware of RetailOS 1.3

This note lists the systems and the sub-systems of the firmware of the iPod
Video. The note gives the evidence of each system. The evidence is a name in
the firmware, not a guess.

> The list is complete for the systems that the firmware names. The firmware
> has no table of all its systems. The list below has 3 kinds of evidence.
>
> - The **table of the tasks** at 0x1025d63c. The firmware has 21 tasks. Each
>   task has a name and the address of the method that makes it. The list is
>   complete for this table.
> - The **names of the classes**. The firmware names its classes in the
>   strings of the image. The script found 49 such names.
> - The **tables of the classes**. The script found 222 class tables with
>   2,127 method slots. Each table has the address of the method of each
>   slot. The constructor of the class sets the first word of the object to
>   the address of the table.

The note does not list the 14,029 functions of the firmware that use no name.
Those are the parts of the library of C and the parts of the drivers of the
hardware.

> The addresses of the methods of the tasks in this note have the base of the
> memory of the iPod. The file `task-table.tsv` has the offset into the image.
> The note [retailos-decompile.md](retailos-decompile.md) explains the 2
> forms of the address.

## The systems

The firmware has 7 systems. The table gives the number of the named parts of
each system.

| The system | The named parts | The task table | The class tables |
|---|---|---|---|
| USB and the computer | 17 | 11 | most of the drivers of the USB |
| Power and the hardware | 9 | 8 | the power controller, the clock |
| The music and the media | 7 | 0 | the video processor, the caches |
| Storage and the file system | 7 | 1 | the file systems, the disk |
| The user interface | 5 | 0 | the views, the lists, the menus |
| The camera and the USB | 3 | 0 | the drivers of the camera |
| Other | 1 | 0 | the base class `Task` |

## USB and the computer

The system of the connection with the computer. The table of the tasks has 11
tasks of this system.

| The task | The method | The work |
|---|---|---|
| `FirewireTask` | 0x10284e58 | The FireWire. The iPod Video has no FireWire port. The task reads the number of the device over the USB. |
| `OptoTask` | 0x10284f90 | The optoelectronic sensor of the wheel. |
| `SerialOptoTask` | 0x1028558c | The optoelectronic sensor of the serial port. |
| `USBPowerSense` | 0x102856a4 | The sense of the power of the USB. |
| `TopPlugTask` | 0x1028564c | The plug at the top of the iPod. |
| `HPhoneDetTask` | 0x10284eb0 | The detection of the headphones. |
| `AccessoryDetectTask` | 0x10284338 | The detection of the accessory of the click wheel. |
| `TopSerAccsryMgr` | 0x10103084 | The accessory of the serial port at the top. |
| `BotSerAccsryMgr` | 0x10103078 | The accessory of the serial port at the bottom. |
| `RsistrAccsryMgr` | 0x100febf8 | The accessory of the resistor of the click wheel. |
| `USBAudioTask` | 0x100c75cc | The audio over the USB. |

The other parts of this system are not in the table of the tasks. The name of
each part is in the strings of the image.

| The name | The work |
|---|---|
| `USBDeviceTask` | The state of the USB device. |
| `USBStatusTask` | The state of the USB. |
| `USBTaskTimeTask` | The time of the tasks of the USB. |
| `USBRoleManager` | The role of the USB. The iPod is a device. |
| `CIapIncomingProcessThread` | The data that comes from the computer. |
| `CIapOutgoingProcessThread` | The data that goes to the computer. |
| `HostOSTask` | The task of the system of the computer. |

The class `eAppAsyncIO` at 0x101e4248 is the class of the input and the
output over the USB. The note [usb-audio.md](usb-audio.md) has 23 functions of
the audio over the USB.

The note [usb-host.md](usb-host.md) gives the full research of the host side of
the stack. The note has 258 functions. The device side has no note.

## Power and the hardware

The system of the power, of the clock and of the hardware of the iPod. The
table of the tasks has 8 tasks of this system.

| The task | The method | The work |
|---|---|---|
| `BacklightTask` | 0x1028453c | The backlight of the screen. |
| `CNATask` | 0x10284a54 | The network of the modem. The iPod has no modem. |
| `HoldSwitchTask` | 0x10284f30 | The switch of the hold. |
| `LowBattDebounceTask` | 0x10284a18 | The filter of the state of the battery. |
| `RTCTimerMgr` | 0x10285460 | The clock of the system. |
| `AlarmTask` | 0x10284374 | The alarm of the system. |
| `WatchdogTask` | 0x102856f0 | The watchdog of the processor. |
| `PCFPowerMgr` | 0x10284ff4 | The power of the computer. |
| `AsyncPiezo` | 0x10285060 | The piezo of the click wheel. |

The other part of this system is not in the table of the tasks.

| The name | The work |
|---|---|
| `PowerManager` | The state of the power. |

The class `eAppMotor` at 0x1024e7fc is the class of the motor of the click
wheel. The class `eAppBlockMgr` at 0x101b085c is the class of the block
manager. The block manager holds the keys of the DRM.

The note [sleep.md](sleep.md) has 32 functions of the sleep. The note
[backlight-timer.md](backlight-timer.md) has 8 functions of the backlight. The
note [piezo.md](piezo.md) has 8 functions of the piezo.

## The music and the media

The system of the music, of the video and of the photos. The table of the tasks
has no task of this system. The names of the parts are in the strings of the
image.

| The name | The work |
|---|---|
| `ArtworkLoadTask` | The load of the covers of the albums. |
| `MP3ExampleTask` | The example of the player of MP3. |
| `PhotoCopyTask` | The copy of the photos to the disk. |
| `TcMemManagerThread` | The manager of the memory of the cache. |
| `TrackCacheReadTask` | The read of the cache of the list of the music. |
| `VCUpdateTask` | The update of the video processor. |
| `VideoDaisyTask` | The video of the Broadcom processor. |

The name `Channel PhotoBrowse` at 0x10212098 and the name
`Channel PhotoImporting` at 0x102120ac are the channels of the photos. The
note [album-art-v2.md](album-art-v2.md) has 22 functions of the covers. The
note [shuffle.md](shuffle.md) has 69 functions of the shuffle.

## Storage and the file system

The system of the disk and of the file system. The table of the tasks has 1
task of this system.

| The task | The method | The work |
|---|---|---|
| `DiskMgrTask` | 0x10284b0c | The manager of the disk. |

The other parts of this system are not in the table of the tasks.

| The name | The work |
|---|---|
| `ATAWorkLoopTask` | The loop of the work of the ATA bus. |
| `ATAWorkLoopIRQTask` | The interrupt of the ATA bus. |
| `DiskReaderTask` | The read of the disk. |
| `StreamCacheReadTask` | The read of the cache of the stream. |
| `StreamCopierReadTask` | The copy of the stream. |
| `StreamCopierWriteTask` | The write of the stream. |

The firmware names the file systems in the strings of the image. The name
`FAT12` is at 0x100c26d8. The name `FAT16` is at 0x100c26e0. The name
`FAT32` is at 0x100c26e8. The name `APPLE_HFS` is at 0x100d1578.

The note [play-latency.md](play-latency.md) has 34 functions of the delay of
the play after the idle time. The delay comes from the flash storage.

## The user interface

The system of the screen and of the input. The table of the tasks has no task
of this system.

| The name | The work |
|---|---|
| `EventManager` | The events of the system. |
| `TimerEventManager` | The events of the clock. |
| `SearchHelperThread` | The help of the search. |
| `TimeManager` | The clock of the user interface. |
| `WindowManager` | The windows of the screen. |

The class `ePresentationEngine` at 0x101fc224 is the class of the engine of
the screen. The engine loads the modules of the screen. The names of the
modules are in the strings of the image: `OpenGLES` at 0x1007947c,
`Filesytem` at 0x1007978c, `Metadata` at 0x10079918, `InputEvents` at
0x10079c44, `Settings` at 0x10079c90 and `AsyncFileIO` at 0x10079bbc.

The note [cover-flow.md](cover-flow.md) has 51 functions of the Cover Flow.
The note [list-rendering.md](list-rendering.md) has 24 functions of the list.

## The camera and the USB

The system of the camera of the iPod Video. The table of the tasks has no task
of this system.

| The name | The work |
|---|---|
| `ICAPTPCameraIOTask` | The input and the output of the camera. |
| `ICAType4CameraDriver` | The driver of the camera of the type 4. |
| `PTPCameraDriver` | The driver of the camera of the protocol of the pictures. |

The camera has no note.

## The DRM and the games

The system of the DRM is not in the table of the tasks. The firmware has a
class for it. The class `eAppBlockMgr` at 0x101b085c holds the keys of the
DRM. The note [games-drm.md](games-drm.md) has 34 functions.

The function `FUN_10175c74` holds the table of the names of the atoms of the
files of the DRM. The table has 83 names. The most important names are the
name `AppleDRM` at 0x101760fc, the name `AppleVideoDRM` at 0x1017713c, the
name `AppleLossless` at 0x10176138, the name `FireWireGUID` at 0x10176594,
the name `FamilyID` at 0x1017657c and the name `BuildID` at 0x1017618c.

## The tables of the classes

The firmware uses a table for each class. The table has the address of the
method of each slot. The script [make-class-map.py](make-class-map.py) found
222 tables with 6 slots or more. The tables have 2,127 slots in all.

The table of the base class of the tasks has 14 slots. 56 tables have 14
slots. 173 of the 222 tables have the same 2 methods in the slots 2 and 3. The
methods are at 0x222de4 and 0x222de8. These methods are the destructor and
the method of the class. The tables of the tasks are these tables.

The table with 17 slots at 0x10676aec is the table of the class of the
application. The constructor is at 0x1022846c. The note
[firmware-functions.md](../docs/firmware-functions.md) gives the vtable of the
application object at 0x66a510. The two tables are different.

The file `class-tables.tsv` has the address of each table, the number of the
slots, the address of the constructor and the addresses of the methods.

## The limits of the list

| The limit | The result |
|---|---|
| The list of the systems | The firmware has no table of all its systems. The list has the 49 names of the tasks, the classes, the managers and the drivers. |
| The functions without a name | 14,029 of the 14,411 functions use no name that the firmware shows. The script cannot name them. |
| The class tables | The script found the tables with 6 slots or more. A class with fewer slots is not in the list. |
| The name of a class | The constructor of a class usually uses no name. The name is in a different function. The script cannot join the two in all cases. |
| The group of a system | The group comes from the name. A task of the group "USB and the computer" can work on the power. |

## The scripts of the research

| The script | The use |
|---|---|
| [make-systems-map.py](make-systems-map.py) | Makes the list of the systems, the groups and the table of the tasks. |
| [make-class-map.py](make-class-map.py) | Makes the list of the tables of the classes and their methods. |
| [make-string-map.py](make-string-map.py) | Makes the map of the strings, the names of the functions and the groups. |

The files of the results are in `~/Library/Application Support/iPodFirm/re/retailos-1.3-decompiled/`.
The folder is not in the repository. The folder holds the image of the firmware.

| The file | The content |
|---|---|
| `systems.tsv` | Each system with its group, its method and its functions. |
| `system-groups.tsv` | The number of the systems of each group. |
| `task-table.tsv` | The table of the tasks of the firmware. |
| `class-tables.tsv` | Each table of a class with its methods. |
| `class-names.tsv` | The names of the tasks and the classes of the image. |

## The next steps

| The step | The work |
|---|---|
| 1 | Join each table of a class to the name of its class. The name is in the function that makes the object. The script must follow the callers of the constructor. |
| 2 | Read the modules of the engine of the screen. The names of the modules are in the strings. The script must find the table of the modules. |
| 3 | Name the 14,029 functions without a name. The callers and the callees give the name. The order of the calls gives the work. |
