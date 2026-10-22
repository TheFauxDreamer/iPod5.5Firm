# The file systems of RetailOS 1.3

This note gives the research of the 4 file systems of the firmware. The
research is the part of the system "Storage and the file system" of the note
[firmware-systems.md](firmware-systems.md). The note
[firmware-storage.md](firmware-storage.md) gives the tasks and the disk.

The addresses are the offsets in the image of the osos. The CPU address of the
code is the offset plus 0x10000000. The note uses the offset.

> This note is the research of the decompilation project. The notes of the
> earlier research stay as they are. The note [games-drm.md](games-drm.md) has
> the research of the check of the DRM. The DRM uses the file system HFSPLUS.

## The summary

The firmware has the code of 4 file systems.

1. The **FAT**. The code has the file systems `FAT12`, `FAT16` and `FAT32`.
   The code of the FAT is at the image 0x7100 to 0x8a48. The code of the FAT
   uses a cipher for the constants. The research did not decode the cipher.
2. The **HFS+**. The code of the HFS+ is at the image 0x9264 to 0xd28c. The
   code reads the volume header, the catalog B-tree and the extents.
3. The **partition table**. The function 0xc22b4 reads the table of the
   partitions of the disk. The function gives the type of the file system of
   each partition.
4. The **dispatcher**. The function 0x34dec has 72,000 characters of code. The
   function has a cipher for the constants. The research did not decode the
   cipher.

The function 0x34dec calls the file systems. The function has 6 arguments. The
function 0x24c08 and the function 0x4af18 call the function 0x34dec.

## The names of the file systems

The names of the file systems are in the strings of the image. The table of the
names is at the image 0xc26d8. Each name has 8 bytes.

| The file system | The name at |
|---|---|
| `FAT12` | 0xc26d8 |
| `FAT16` | 0xc26e0 |
| `FAT32` | 0xc26e8 |

The name `HFSPLUS` is at the image 0x176c14. The name is in the table of the
DRM. The name `FAT32` is also at the image 0x176c50, at the image 0x17755c and
at the image 0x1fb834.

The function 0x34dec uses the 3 names of the table at 0xc26d8. The function
0xc22b4 uses the same 3 names.

## The table of the partitions

The function 0xc22b4 reads the table of the partitions of the disk. The
function reads 4 partitions. The function reads the first sector of the disk
with the function 0x228fa4 and the function 0x2290a0.

The function checks the signature 0xaa55 at the offset 510 of the sector. The
value 0xaa55 is at the image 0xc26f0. The function gives the number 0xaa55
when the signature is not there.

The function reads the 4 entries of the table of the partitions. Each entry
has 8 bytes. The entry is at the offset 0xdf of the buffer of the sector. The
byte at +0 of the entry is the type of the partition. The byte at +2 of the
entry is the type of the file system.

| The type of the file system | The value |
|---|---|
| The partition is not known | 0 |
| The partition is FAT12 | 1 |
| The partition is FAT16 | 4 |
| The partition is FAT32 | 6 |
| The partition is a partition of the system | 0xb |
| The partition is FAT32 with a cluster of 32 bits | 0xc |
| The partition is a partition of the disk of the firmware | 0xe |

The function compares the name of the file system at the offset 0x1b of the
buffer with the 3 names of the table at 0xc26d8. The function compares the
name at the offset 0x29 of the buffer in the same way.

The function gives the number 3 for the file system FAT12, the number 4 for
the file system FAT16 and the number 5 for the file system FAT32. The
function gives the number 0xb for the file system HFSPLUS.

The function reads the name of the file system with the function 0x7ceb8. The
function reads the length of the name. The function compares the name of the
file system of the partition with the names of the other partitions. The
function sets the state of the partition to 0 when 2 partitions have the same
name.

## The file system HFS+

The code of the HFS+ is at the image 0x9264 to 0xd28c. The code reads the
volume header, the catalog B-tree and the extents of the files.

### The signature of the volume

The function 0x93c4 and the function 0x95a0 read the header of the volume.
The function looks for the 2 signatures.

| The signature | The name at | The meaning |
|---|---|---|
| `Standard_Eta` | 0x96c0 | The volume is HFS+. The signature is at the offset 0 of the sector of the volume. |
| `STANDARD` | 0x96d0 | The volume is HFS. The signature is at the offset 0 of the sector of the volume. |

The function 0x95a0 reads the signature `Standard_Eta` with 12 bytes. The
function 0x93c4 reads the signature `Standard_Eta` with 12 bytes and the
signature `STANDARD` with 8 bytes.

The function 0x95a0 gives the number 4 when the volume is not there. The
function gives the number 7 when the name of the volume is too short. The
function gives the number 5 when the type of the volume is not 3 or 4. The
function gives the number 8 when the type of the volume is not in the range of
1 to 10. The function gives the number 9 when the data of the volume is not
there. The function gives the number 0xb when the name of the data of the
volume is too short.

### The header of the volume

The function 0xc034 reads the header of the volume of HFS+. The function fills
an object of the volume.

| The offset of the object | The part of the header | The size |
|---|---|---|
| +0x00 | The number of the sector of the volume. | 4 |
| +0x04 | The signature and the version. | 0x200 |
| +0x208 | The number of the first sector of the catalog. | 4 |
| +0x20c | The number of the first sector of the extents. | 4 |
| +0x210 | The number of the first sector of the allocation. | 4 |
| +0x214 | The number of the first sector of the attributes. | 4 |
| +0x218 | The rest of the header. | 0x34 |
| +0x24c | The number of the sector of the file of the startup. | 4 |
| +0x250 | The rest of the header. | the size of the volume - 0x24c |

The function 0xc034 copies the first 0x200 bytes of the header. The function
reads 4 numbers of the header with the function 0x9da4. The function 0x9da4
converts the number. The conversion depends on the byte order of the disk.

The function 0x9da4 and the function 0x9dd8 change the byte order of a 32
bit number. The function 0x9e0c changes the byte order for 3 cases.

The function 0xc034 looks for the signature `Standard_Eta` at the image
0xbf08. The function 0xbf18 reads the header of the volume in the same way.

### The tree of the catalog

The code reads the catalog B-tree. The functions of the tree are at the image
0xb800 to 0xcb34.

| The function | The work |
|---|---|
| 0xb800 | Reads the node of the tree. The function reads 2 numbers. The numbers are the kind of the node. |
| 0xb8c8 | Reads the kind of the node and the number of the node. |
| 0xb9a0 | Reads the name of a record of the tree. The function compares the name with the function 0x7cdd4. |
| 0xbaf0 | Reads the data of a record of the tree. |
| 0xbf18 | Reads the header of the volume. |
| 0xc034 | Reads the header of the volume. |
| 0xc140 | Reads the node of the tree of the volume. |
| 0xc1c8 | Reads the record of the tree. |
| 0xc264 | Reads the node of the tree of the volume. |
| 0xc300 | Looks for a name in the catalog. |
| 0xc408 | Looks for a name in the catalog. |
| 0xc510 | Looks for a name in the catalog. |
| 0xc628 | Looks for a name in the catalog. |
| 0xc744 | Looks for a name in the catalog. |
| 0xc868 | Looks for a name in the catalog. |

The 2 kinds of the node are at the image 0xbf00 and 0xbf04. The kinds are the
numbers 0x44332211 and 0x11223344.

The function 0xc300 and the function 0xc510 use the function 0x7b5ec. The
function 0x7b5ec reads the next node of the tree.

### The records of the catalog

The code reads the records of the catalog. The functions are at the image
0xaf8c to 0xb54c.

| The function | The work |
|---|---|
| 0xaf8c | Reads the record of a file. The function reads the name of the file and the data of the file. |
| 0xb104 | Reads the record of a file. The function reads the name of the file and the data of the file. |
| 0xb27c | Reads the record of a folder. The function reads the name, the number of the files and the number of the folders. |
| 0xb54c | Reads the record of a folder. The function reads the name, the number of the files and the number of the folders. |

The functions use the 6 functions of the offset. The functions move the
pointer of the record.

| The function | The work |
|---|---|
| 0xa1ec | Moves the pointer by a number of bytes. |
| 0xa204 | Moves the pointer by a number of words. |
| 0xa21c | Moves the pointer by a number of 16 bit values. |
| 0xa23c | Moves the pointer by a number of 32 bit values. |
| 0xa260 | Moves the pointer by a number of values of a size. |
| 0xa288 | Moves the pointer by a number of values of a size. |

The function 0xb27c reads the name of the folder and the 3 numbers of the
folder. The numbers are the number of the files, the number of the folders and
the number of the bytes of the data.

### The cipher of the constants

The code of the HFS+ has 2 ciphers for the constants. The functions are at the
image 0xa6e4 to 0xade0.

| The function | The work |
|---|---|
| 0xa6e4 | Changes the 4 words of 4 bytes with a table of 256 bytes. |
| 0xa720 | Changes the 4 words of 4 bytes with a table of 256 bytes. |
| 0xa75c | Changes the order of the bytes of a value. |
| 0xa7c0 | Changes the order of the bytes of a value. |
| 0xa824 | Changes the value with a table. |
| 0xa988 | Changes the value with a table. |
| 0xab18 | Changes the 4 words of 4 bytes with a key of 16 bytes. |
| 0xab58 | Changes the 4 words of 4 bytes with a key of 16 bytes. |
| 0xac40 | Changes the 4 words of 4 bytes with a key of 16 bytes. |
| 0xad24 | Changes the 16 bytes of a key with a key. |
| 0xade0 | Changes the 16 bytes of a key with a key. |

The tables of the cipher are at the image 0xa69c and 0xa6b0. The table of the
cipher of 0xab18 is at the image 0xaf10. The table of the cipher of 0xa720 is
at the image 0xaf14.

The research did not decode the cipher of the FAT. The research did not
decode the cipher of the dispatcher.

## The file system FAT

The code of the FAT is at the image 0x7100 to 0x8a48. The code of the FAT has
a cipher for the constants. The constants of the FAT are at the image 0x77f0
to 0x7840. The research did not decode the cipher.

| The function | The work |
|---|---|
| 0x7100 | Copies the clusters of the FAT. The function reads the table of the clusters. |
| 0x7278 | Changes the bytes of a value with the cipher. |
| 0x7c14 | Copies the clusters of the FAT. |
| 0x7d84 | Reads a record of the directory of the FAT. |
| 0x7f3c | Reads a record of the directory of the FAT. |
| 0x8140 | Reads the file of the FAT. The function has 24 arguments. |
| 0x8a48 | Reads the file of the FAT. The function has 24 arguments. |

The function 0x8a48 is called by the dispatcher 0x34dec. The function 0x7d84
is called by the function 0x49730. The function 0x7f3c is called by the
function 0x73ce0.

## The limits of the research

| The limit | The result |
|---|---|
| The cipher of the FAT | The code of the FAT has a cipher for the constants. The research did not decode the cipher. The research did not name the fields of the boot sector of the FAT. |
| The cipher of the dispatcher | The function 0x34dec has 72,000 characters of code. The function has a cipher for the constants. The research did not decode the cipher. |
| The tree of the catalog | The research found the 2 kinds of the node and the 6 functions of the offset. The research did not name the fields of the node of the tree. |
| The header of the volume | The research found the 2 signatures and the offsets of the 5 files. The research did not name all the fields of the header. |
| The partitions | The function 0xc22b4 reads the 4 partitions. The research did not trace the reading of the table of the partitions of the disk. |
| The 4 file systems | The research found the code of the FAT and the code of the HFS+. The research found no separate code for the file system FAT12, FAT16 or FAT32. The 3 names select the mode of the same code. |
