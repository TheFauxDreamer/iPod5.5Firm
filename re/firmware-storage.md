# The storage and the file system of RetailOS 1.3

This note gives the research of the system "Storage and the file system" of the
note [firmware-systems.md](firmware-systems.md). The system has 7 named parts.
The parts are the task `DiskMgrTask` and 6 other names.

The note gives the tasks, the bus of the disk, the file systems and the
partitions.

The addresses are the offsets in the image of the osos. The CPU address of the
code is the offset plus 0x10000000. The note uses the offset.

> This note is the research of the decompilation project. The notes of the
> earlier research stay as they are. The note
> [play-latency.md](play-latency.md) gives the delay of the play after the idle
> time. The delay comes from the storage.

## The summary

The iPod Video has a disk with a flash or a hard disk. The firmware has 3
parts.

1. The **bus of the disk**. The bus is the ATA of the older iPod. The firmware
   has a task for the work of the bus and a task for the interrupt of the bus.
2. The **file systems**. The firmware has the file systems `FAT12`, `FAT16`,
   `FAT32` and `HFSPLUS`. The iPod uses the file system of the format of the
   disk.
3. The **partitions**. The firmware reads the table of the partitions of the
   disk.

## The tasks of the system

The table of the tasks of the firmware is at 0x25d63c. The table has 21 tasks.
1 of the tasks belongs to this system.

| The task | The method | The work |
|---|---|---|
| `DiskMgrTask` | 0x284b0c | The manager of the disk. |

The other 6 parts of the system are not in the table of the tasks. Each task is
made at the run time.

| The task | The name | The function that makes it | The stack | The priority | The events |
|---|---|---|---|---|---|
| `ATAWorkLoopTask` | 0x186bbc | 0x186b34 | 0xc0 | 0x800 | 0 |
| `ATAWorkLoopIRQTask` | 0x186bd0 | 0x186b34 | 0xc0 | 0x800 | 0 |
| `DiskReaderTask` | 0x1777b4 | 0x17775c | 8 | 0x800 | 0 |
| `StreamCacheReadTask` | 0x20be64 | 0x20be1c | 8 | 0x4000 | 0 |
| `StreamCopierReadTask` | 0x500b74 | 0x1ddc50 | — | — | — |
| `StreamCopierWriteTask` | 0x500b5c | 0x1ddc50 | — | — | — |

The note [firmware-media.md](firmware-media.md) gives the task of the cache of
the stream and the 2 tasks of the copy of the stream.

### The tasks of the bus of the disk

The function 0x186b34 makes the 2 tasks of the bus of the disk. The function
calls the function 0x1435a0 and puts the result at +8 of the object. The
function then calls the function 0x11c808 twice with the same argument string
of 0x20 bytes.

The name `ATAWorkLoopTask` is at the image 0x186bbc. The name
`ATAWorkLoopIRQTask` is at 0x186bd0. The size of the stack of the 2 tasks is
0xc0. The priority of the 2 tasks is 0x800.

### The task of the reader of the disk

The function 0x17775c makes the object of the task `DiskReaderTask`. The
function makes the task with the size of the stack 8, the priority 0x800 and
the number of the events 0. The name of the task is at the image 0x1777b4.

### The manager of the disk

The method 0x284b0c is the task `DiskMgrTask`. The method has a table of 0x2d
entries at 0x284e4c. Each entry is the state of a partition. The method fills
the table with 0 at the start.

The method then reads the number of the partitions with the function 0xa631c.
The method reads each partition with the function 0xa66a4 or the function
0xa6650. The method then calls the function 0x2651e4 to read the state of the
disk. The method sets the state of the partition and gives the number of the
partition at +4 of the table at 0x284e50.

The names of the events of the disk are in the strings of the image. The name
"Disk Activity" is at 0x212b68. The name "Disk Spinup" is at 0x213dcc. The name
"Disk Spindown" is at 0x213dd8. The name "Disk Obtain Access" is at
0x213de8. The name "Disk Release Access" is at 0x213dfc.

## The file systems

The firmware has 4 file systems. The names of the file systems are in the
strings of the image.

| The file system | The name at |
|---|---|
| `FAT12` | 0xc26d8 |
| `FAT16` | 0xc26e0 |
| `FAT32` | 0xc26e8 |
| `HFSPLUS` | 0x176c14 |

The names of the file systems are in a table of 8 bytes per name at 0xc26d8.
The function 0x34dec uses the 3 names of the table of 0xc26d8. The function
is the dispatcher of the file systems. The function takes 6 arguments. The
function is called by the function 0x24c08 and the function 0x4af18.

The names of the file systems are also in the table of the DRM at 0x176c14.
The table has the name `HFSPLUS` and the name `FAT32` at 0x176c50. The name
`FAT32` is also at 0x17755c and at 0x1fb834.

## The partitions

The firmware reads the table of the partitions of the disk. The manager of the
disk has a table of 0x2d entries. The iPod has 2 partitions: the partition of
the data and the partition of the firmware.

The names of the parts of the disk are in the strings of the image. The name
"CorruptDataPartition" is at 0x177058. The name "CorruptFirmwarePartition" is
at 0x177070. The name "BangFolder" is at 0x17704c. The name
"ForcedDiskMode" is at 0x177038.

## The limits of the research

| The limit | The result |
|---|---|
| The file systems | The research found the 4 names of the file systems and the dispatcher at 0x34dec. The research did not decode the 4 file systems. The dispatcher has 72,000 characters of code. |
| The partitions | The research found the table of 0x2d states and the names of the parts of the disk. The research did not trace the function that reads the table of the partitions. |
| The bus of the disk | The research found the 2 tasks and their parameters. The research did not trace the work of the tasks. |
| The ATA registers | The registers of the ATA are in the region 0xC3000000. The note [../docs/firmware-functions.md](../docs/firmware-functions.md) has the table of the registers. |
| The task `DiskMgrTask` | The method 0x284b0c is the manager of the disk. The research did not trace the work of the method. |

## The sources

- The image of the osos: `~/Library/Application Support/iPodFirm/re/osos-1.3.bin`
- The decompiler: Ghidra 12.1.4, with the script `DecompileAt.java` of the folder [ghidra-scripts](ghidra-scripts)
- The note of the delay of the play: [play-latency.md](play-latency.md)
- The note of the music: [firmware-media.md](firmware-media.md)
