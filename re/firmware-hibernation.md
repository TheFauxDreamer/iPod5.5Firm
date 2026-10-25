# The hibernation of the iPod: the image `hibe` in full

This note gives the result of the research of the hibernation of the iPod Video.
The research answers four questions.

1. What is the image `hibe` and what is in it?
2. Which code writes the image and which code reads it?
3. What makes the iPod hibernate?
4. Where does the image live in the program?

The result is in the first section of each part. The research gives the
evidence. The reference [../docs/firmware-functions.md](../docs/firmware-functions.md)
gives the short form.

The note continues the research of [firmware-hibe.md](firmware-hibe.md). That
note found that a flash removed the image `hibe` of the iPod. This note gives
the whole mechanism of the hibernation.

## The result in short

| The question | The answer |
|---|---|
| What is the image `hibe`? | A snapshot of the SDRAM of the iPod, 64 MB and 2 KB. The image has a header of 0x800 bytes and a payload of 64 MB. The header holds a mask of the 64 pages that are saved. The iPod writes the image when it sleeps. |
| Which code writes the image? | The bootloader in the NOR flash, not the `osos`. The `osos` calls three functions in the bootloader through thunks. The function at 0x10000388 sets up the image at the start of the `osos`. |
| Which code reads the image? | The same function at 0x10000388. The function reads the image and gives the memory back to the `osos`. |
| What makes the iPod hibernate? | Two settings in the file `iPod_Control/Device/`. The setting `_hibe_sleep` makes the iPod hibernate at each sleep. The value must not be 0. The setting `_disable_hibe` turns the hibernation of the alarm off. The value must be 0. The function 0xb43dc reads the first value and enters the power mode 3 instead of the mode 2. The task of the alarm reads the second value. The bootloader writes the image. |
| Where does the image live? | In the file `hibe` of the firmware partition, at the place 0x00d43800, 64 MB and 2 KB. The place never changes. |

> The image `hibe` is the only image of the partition that the firmware does
> not check. The `checksum` field of its entry is 0. The image is a copy of the
> memory, not code.

## Part 1: the image `hibe`

### The result

The image `hibe` is a copy of the SDRAM of the iPod. The image has a header of
0x800 bytes and a payload of 64 MB. The size of the image is 0x04000800 bytes.

The header has five fields. The research read them from the images of the
backups of the owner.

| The place | The size | The content |
|---|---|---|
| 0x00 | 4 | The version of the format. The value is 1. |
| 0x04 | 4 | The size of a page of the memory. The value is 0x20000, 128 KB. |
| 0x08 | 4 | The number of the pages of the memory. The value is 0x40, 64. |
| 0x0c | 4 | 0xffffffff. |
| 0x10 | 4 | 0xffffffff. |
| 0x14 | 8 | The mask of the pages that are saved. 64 bits, one bit for each page. |
| 0x18 | 0x24 | The pattern of the pages that are not saved. |
| 0x3c | 0x14 | The end of the pattern. |
| 0x50 | 0x7b0 | Zero. |

The payload starts at the place 0x800 of the image. The payload is the memory
of the iPod. The memory is mapped at the place 0, thus the payload holds the
`osos` at the place 0x1000 of the payload. The research found the strings of
the `osos` in the payload.

| The place in the payload | The place in the `osos` | The string |
|---|---|---|
| 0x0020 | 0x000020 | `portalplayer` |
| 0x0534 | 0x100538 | `!ATAebih` |
| 0x1000 | 0x101000 | `booting!` |
| 0x100c | 0x10100c | `hotstuff` |

The place 0x0534 of the payload holds the names `!ATA` and `ebih`. The names
are the same as the names in the `osos` at the place 0x100538. The proof is the
string `!ATAebih` in the payload.

> The payload is a copy of the memory of the iPod. The copy holds the `osos` and
> the strings of the bootloader. The `osos` reads the image at the start and
> gives the memory back.

The image of the owner of 1 October 2026 has 33 pages saved. The mask is
0x44444444447fffff. The bits 0 to 21, 26 and 30 of the low word are set, and
the bits 30, 34, 38 and 42 of the high word are set.

### The evidence of the mask

The research compared the four images of the owner. The version, the size of a
page and the number of the pages are the same in all of them. Only the mask and
the pattern change.

| The backup | The mask | The pages | The pattern |
|---|---|---|---|
| Original (first backup).bin | 0x44444444447fffff | 33 | 0x44 |
| 2026-10-06 09.42.00 before flash.bin | 0x88888888888fffff | 31 | 0x88 |
| 2026-10-22 22.09.32 before flash.bin | 0x11111111111fffff | 31 | 0x11 |
| 2026-10-23 21.12.33 before flash.bin | 0x88888888888fffff | 31 | 0x88 |

The mask has 64 bits. The number of the pages in the header is 64. Thus each
bit of the mask says if the memory of that page is in the image. The pages that
the mask does not set have the pattern of the header instead of the memory.

The pattern of the header is the same byte in all the pages. The byte is the
pattern of the memory that the iPod had at the time of the snapshot. The
research did not find the code that makes the pattern.

## Part 2: the code of the `osos`

### The result

The `osos` does not write the image and does not read it. The `osos` asks the
bootloader in the NOR flash to do both. The `osos` has one function for the
setup of the image and it runs at the start of the `osos`.

### The function at 0x10000388

The function `FUN_10000388` is the setup of the image. The function runs at
the start of the `osos`. The research found it with the script
`FindConstant.java`: the function is the only one that uses the names `!ATA`
and `ebih` of the `osos`.

The names are next to each other at the place 0x10000538 of the `osos`.

| The place | The bytes | The content |
|---|---|---|
| 0x10000534 | `21 41 54 41` | `!ATA` |
| 0x10000538 | `65 62 69 68` | `ebih` |

The function does these steps.

```c
uVar1 = uRam10000538;              // "ebih"
uVar3 = uRam10000534;              // "!ATA"
FUN_10265598(&uStack_c0,&uStack_c4);   // the size of the RAM and the block size
uStack_3c = uVar1;
uStack_40 = uVar3;
uStack_38 = 1;
uStack_30 = uStack_c4;

// the lookup of the image "ebih", the kind 1 and then the kind 0
iVar2 = thunk_EXT_FUN_40003260(uVar1,1,auStack_68);
if (((iVar2 == 0) || (iVar2 = thunk_EXT_FUN_40003260(uVar1,0,auStack_68), iVar2 == 0)) &&
   (iStack_58 == uStack_30 + 0x800)) {
  uVar4 = 1;                        // the image is good
  uStack_34 = uStack_5c;
  uStack_36 = uStack_5e;
  if (sStack_60 == 0) {
    thunk_EXT_FUN_40003400(auStack_68,&uStack_40);   // read the image
  }
}
uStack_b0 = 0x20000;                // the size of a page
uStack_b4 = 1;
uStack_ac = uStack_c4 >> 0x14;      // the number of the pages
uVar3 = FUN_100f3854();
FUN_1028278c(auStack_a8,uVar3,0x40);
iVar2 = thunk_EXT_FUN_40001a34(&uStack_40,&uStack_b4,uStack_bc,uStack_b8,uVar4);  // write the image
if ((iVar2 == 0) && (iVar2 = thunk_EXT_FUN_40003260(uVar1,1,auStack_68), iVar2 == 0)) {
  FUN_100000f0(&uStack_40,auStack_68,0x28);   // copy the directory entry
  uStack_38 = 0;
  thunk_EXT_FUN_40003400(auStack_68,&uStack_40);
}
```

The function does two things.

1. **It reads the image.** The function looks for the image `ebih` in the
   directory of the partition. The function checks that the end of the image is
   0x800 bytes after the value of the disk. If the check passes, the function
   gives the memory of the image back with the function at 0x40003400.
2. **It writes the image.** The function writes the image with the function at
   0x40001a34. The function uses the size of a page 0x20000 and the number of
   the pages. Then the function copies the entry of the image into the directory
   of the partition with the function at 0x100000f0.

The function at 0x100000f0 is a copy of the memory. It copies 0x20 bytes at a
time. The size of the copy is 0x28, 40 bytes: the size of one entry of the
directory.

> The `osos` never reads the content of the image. The `osos` only asks the
> bootloader to give the memory back. The bootloader does the work.

### The three functions of the bootloader

The three functions are outside the `osos`. The research found them as
`EXT_FUN_4000xxxx` in the decompilation.

| The address | The work | The direction |
|---|---|---|
| 0x40003260 | The lookup of the image in the directory of the partition. It takes the name `ebih` and the kind 1 or 0. | Both |
| 0x40003400 | The read of the image. It gives the memory of the image to the `osos`. | The read |
| 0x40001a34 | The write of the image. It takes the number of the pages, the size of a page and a flag that says if the image is good. | The write |

The address 0x40000000 is the **IRAM** of the iPod. The bootloader in the NOR
flash copies itself to the IRAM and runs there. The research of the emulator
confirms this: the note [16-the-third-bootloader.md](../emulator-src/research/16-the-third-bootloader.md)
of the emulator says that the loader "relocated itself to IRAM correctly (every
PC above is `0x4000xxxx`, which is where `startup.s` says it copies itself)".

### The bootloader and the `sysinfo_t`

The function `FUN_10265598` gives two values of the object of the disk. The
function reads the places 0xe0 and 0xe4 of the object.

The research of the emulator found the structure of the object: the
`sysinfo_t` of the bootloader. The note
[02-retailos-boot.md](../emulator-src/research/02-retailos-boot.md) of the
emulator gives the structure and the source of the public documentation.

| The place | The content |
|---|---|
| 0x4001ff18 | The tag `IsyS`. |
| 0x4001ff1c | The pointer to the `sysinfo_t`. |

The place 0xe0 of the `sysinfo_t` is inside the field `pad7[120]` of the
structure of iPodLinux. The `osos` reads the size of the RAM from that place.
The research of the emulator measured this: "RetailOS reads its RAM size from
`[sysinfo + 0xe0]`".

The value 0xe0 is thus the size of the RAM of the iPod. The function
`FUN_10265598` gives it to the function at 0x10000388. The function shifts the
value by 0x14 to get the number of the pages: `uStack_ac = uStack_c4 >> 0x14`.

The size of the RAM of the iPod Video is 0x4000000, 64 MB. The shift by 0x14
gives 0x40, 64. The header of the image holds 0x40, 64, in all the images of
the owner. The two values agree.

> The number of the pages in the header is the size of the RAM in MB. The
> research proved this with the shift of 0x14 in the code of the `osos`.

## Part 3: the trigger

### The result

The `osos` decides when the iPod hibernates. The decision uses two settings of
the file `iPod_Control/Device/`. The names of the settings are `_hibe_sleep`
and `_disable_hibe`.

The iPod hibernates at each sleep when the setting `_hibe_sleep` is not 0. The
iPod sleeps without hibernation when the setting is 0.

The iPod hibernates when the alarm sounds when the setting `_disable_hibe` is
0. The iPod stays awake when the setting is not 0.

| The place | The content |
|---|---|
| `iPod_Control/Device/_hibe_sleep` | The value of the setting. The value 0 means no hibernation. |
| `iPod_Control/Device/_disable_hibe` | The value of the setting. The value 0 means the hibernation of the alarm. |
| 0x1081dfe7 | The byte of `_hibe_sleep` in the memory. |
| 0x1081dfe8 | The byte of `_disable_hibe` in the memory. |
| 0x100b4628 | The pointer to the byte of `_hibe_sleep`. The function 0xb43dc reads it. |

The values of the settings are read once, at the start of the `osos`. The bytes
at 0x1081dfe7 and 0x1081dfe8 hold the values from that moment on.

### The path

The path of the sleep of [sleep.md](sleep.md) gives the way to the decision.
The research added the two steps that choose the power mode.

| The step | The function | The work |
|---|---|---|
| 1 | 0x1d83fc | The item of the menu Sleep. The function turns the backlight off and starts the idle timer. |
| 2 | 0x1d8a40 | The handler of the idle timer. The function waits for the gate 0x1d938c. |
| 3 | 0x1ee8d0 | The function saves the settings and empties the memory cache. |
| 4 | 0x1dfdd4 | The function calls the sleep function. |
| 5 | 0xb43dc | The sleep function. The function reads the flag of hibernation and enters the power mode 3 or 2. |
| 6 | the bootloader | The bootloader writes the image `hibe` and stops the drive. |

The research decompiled the function 0xb43dc. The function reads two values.

```c
uVar2 = param_1;
if (param_2 == 0) {
  uVar2 = (uint)*DAT_100b4628;      // the flag of hibernation
}
bVar8 = uVar2 != 0;
bVar1 = param_2 != 0;
...
if (bVar1 || bVar8) {
  FUN_102823bc(3,1,1);             // the power mode 3: the hibernation
  thunk_EXT_FUN_400003c8();
  FUN_10283e20(1);
}
else {
  FUN_102823bc(2,1,1);             // the power mode 2: the sleep
  ...
}
```

The function enters the power mode 3 when the second parameter is not 0, or
when the flag of hibernation is not 0. The function enters the power mode 2
otherwise.

The instruction at 0x100b43e8 loads the pointer `0x1081dfe7`. The research
proved this with the script `FindConstant.java`. The search found only two
uses of the value: the function 0xb43dc and the accessor at 0x101d3c2c.

### The byte of the sleep object

The function 0x1dfdd4 asks the sleep object for one more value. The function
calls the method of the table of virtual functions at the offset 0xf0.

```c
uVar2 = (**(code **)(*param_1 + 0xf0))(param_1);
iVar3 = 1 - uVar2;
if (1 < uVar2) {
  iVar3 = 0;
}
FUN_1018ab34(param_1,0);
if (iVar3 != 0) {
  FUN_10095ef0();
}
FUN_100b43dc(iVar3,param_2);
```

The method at the offset 0xf0 of the table is the function 0x1018ab24. The
research found the table at 0x10670778. The function is small.

```asm
1018ab24  e5d00018  ldrb r0, [r0,#0x18]
1018ab28  e12fff1e  bx lr
```

The function gives the byte at the offset 0x18 of the sleep object. The value
0 means that the iPod hibernates. The function 0x1dfdd4 then calls the
function 0x10095ef0 and passes the value 1 to the sleep function 0xb43dc.

The byte at the offset 0x18 of the sleep object is a second way to force the
hibernation for one sleep only. The setting `_hibe_sleep` is the way that
lasts.

### The setting

The research found the setting with the script `FindConstant.java`. The
function `FUN_101d42b8` writes the byte at 0x1081dfe7. The function is a
normal reader of the settings of the device.

```c
void FUN_101d42b8(void)
{
  undefined1 auStack_34 [36];
  undefined1 uVar1;

  local_10 = DAT_101d4334;      // the name of the setting, coded
  local_c = DAT_101d4338;
  local_8 = DAT_101d433c;
  FUN_1007cd6c(auStack_34,s_iPod_Control_Device__101d4340);  // the path
  FUN_1007cf2c(auStack_34,&local_10);                        // the name
  uVar1 = FUN_10122a0c(auStack_34,0);
  *(undefined1 *)(DAT_101d4358 + 0xb) = uVar1;                // the byte
}
```

The pointer `DAT_101d4358` is 0x1081dfdc. The byte is at the offset 0xb of
this place. The byte is 0x1081dfe7.

The name of the setting and the path are coded in the firmware. Each byte of
the text is the byte of the text moved to the right by one bit. The research
decoded the text at 0x101d4334.

```text
raw   bed0d2c4cabee6d8cacae0b
coded _hibe_sleep
```

The path at 0x101d4340 is `iPod_Control\Device\`. The full name of the setting
is thus `iPod_Control/Device/_hibe_sleep`.

The function `FUN_101d42b8` runs in the function `FUN_101d3ac4`. That function
reads all the settings of the device at the start of the `osos`. The research
proved this with the script `CallerTree.java`.

The same function reads the other settings of the device in the same way. The
research decoded their names.

| The name | The place | The meaning |
|---|---|---|
| `_hibe_sleep` | 0x101d4334 | The hibernation is on when the value is not 0. |
| `_disable_hibe` | 0x101d48b8 | The hibernation of the alarm is off when the value is not 0. |
| `_sync_any_video` | 0x101d3f44 | The sync of the video is on. |
| `_enable_a46_remote_menu` | 0x101d4024 | The menu of the remote of the radio is on. |
| `FirstTime` | 0x101d3e9c | The first time that the iPod runs. |

### The setting `_disable_hibe`

A second setting turns the hibernation of the alarm off. The setting is
`_disable_hibe`. The function `FUN_101d4834` reads it at the start of the
`osos`.

```c
void FUN_101d4834(void)
{
  ...
  FUN_1007cd6c(auStack_3c,s_iPod_Control_Device__101d48c8);   // the path
  FUN_1007cf2c(auStack_3c,&local_14);                         // the name
  uVar1 = FUN_10122a0c(auStack_3c,0);
  *(undefined1 *)(DAT_101d48e0 + 0xc) = uVar1;                 // the byte
}
```

The byte is at 0x1081dfe8. The task of the alarm reads the byte. The task is
the function `FUN_10284374`. The note [firmware-power.md](firmware-power.md)
gives the task of the alarm.

```c
if (iVar4 == 0x94) {          // the event of the alarm
  ...
  if (*DAT_102844d8 == '\0') {
    FUN_100a7774();          // the iPod hibernates
  }
  else {
    FUN_10094e08();          // the iPod stays awake
    FUN_102666e0();
  }
}
```

The pointer `DAT_102844d8` is 0x1081dfe8. The value 0 means that the iPod
hibernates when the alarm sounds. A value that is not 0 means that the iPod
stays awake.

> The `osos` has no code for the image `hibe` other than the setup at the
> start. The write of the image is in the bootloader. The research could not
> follow the bootloader, because the copy of the NOR flash of the iPod is not on
> the machine of the owner.

> The trigger of the hibernation is thus a file on the iPod. The owner can
> turn the hibernation on and off with the file
> `iPod_Control/Device/_hibe_sleep`. The file holds one byte. The value 0
> means that the iPod sleeps without hibernation. The value 1 means that the
> iPod hibernates.

## Part 4: the capability of the iPod

### The result

The `osos` tells the computer that the iPod can hibernate. The property is the
`CanHibernate` of the USB device. The `osos` also tells the size of the RAM.

### The table of the names

The `osos` holds the names of the properties of the device. The names are next
to each other in the data area, at the place 0x100177033.

| The place | The name |
|---|---|
| 0x1001770a0 | `CanHibernate` |
| 0x1001770b0 | `RAM` |
| 0x1001770b4 | `HotPlugState` |
| 0x1001770c4 | `SortFieldsSupported` |
| 0x1001770d8 | `vCardWithJPEGSupported` |
| 0x1001770f0 | `MaxFileSizeInGB` |
| 0x100177100 | `GamesPlatformID` |
| 0x100177110 | `GamesPlatformVersion` |
| 0x100177128 | `VideoCodecs` |
| 0x100177038 | `ForcedDiskMode` |
| 0x10017704c | `BangFolder` |
| 0x100177058 | `CorruptDataPartition` |
| 0x100177070 | `CorruptFirmwarePartition` |
| 0x10017708c | `CanFlashBacklight` |

### The function that fills the properties

The function `FUN_10175c74` builds the list of the properties. The function
writes the `CanHibernate` and the `RAM`.

```c
FUN_101485c8(param_1 + 0xc,s_CanHibernate_101770a0,*(undefined1 *)(param_1 + 0x1f0),1);
if (*(int *)(param_1 + 500) != 0) {
  FUN_101483f0(param_1 + 0xc,&DAT_101770b0,*(int *)(param_1 + 500),1);
}
```

The function `FUN_101774a0` sets the two values. The function runs when the
device object is made.

```c
uVar1 = FUN_000ecfcc();
*(undefined1 *)(param_1 + 0x1f0) = uVar1;      // the flag CanHibernate
FUN_10265598(0,&local_18);
*(uint *)(param_1 + 500) = local_18 >> 0x14;     // the size of the RAM
```

The function `FUN_000ecfcc` gives 1. The research decompiled the function.

```c
undefined4 FUN_000ecfcc(void)
{
  return 1;
}
```

The size of the RAM in the property `RAM` is the size of the RAM in MB, from
the same shift of 0x14 as in the setup of the image. Thus the property `RAM` and
the word 3 of the header of the image hold the same value.

> The iPod Video always tells the computer that it can hibernate. The flag is
> not a switch. The size of the RAM is the size of the RAM of the iPod, from
> the `sysinfo_t` of the bootloader.

## The work that is left

The research gives these tasks.

1. Get the copy of the NOR flash of the iPod of the owner. The research needs
   it to follow the three functions of the bootloader: the lookup at
   0x40003260, the read at 0x40003400 and the write at 0x40001a34. The research
   could not follow them: the functions are in the NOR flash, and the copy of
   the NOR flash is not on the machine of the owner.
2. Find the code that makes the pattern of the pages that are not saved. The
   research found the pattern in the header of the image, but not the code.
3. Find the meaning of the bits of the mask. The research proved that the bit
   does not say if the page has data in the image. The research did not find
   the meaning.
4. Find the code that reads the image `hibe` in the bootloader. The function
   `FUN_10000388` gives the memory back with the function at 0x40003400. The
   research did not follow the function.
5. Test the setting `_hibe_sleep` on the iPod of the owner. The research needs
   the iPod to sleep with the value 1 and with the value 0. The research needs
   to measure the size of the image `hibe` after each sleep. The research also
   needs to find the code that writes the byte at the offset 0x18 of the sleep
   object. This byte can force the hibernation for one sleep. The research did
   not find the code that writes the byte.
