# Search on the iPod 5G

This note records the research for the patch `search-5g`. All addresses are osos offsets for RetailOS 1.3 (`iPod_25.1.3.ipsw`). The Ghidra project is `osos13` (base address 0x0). The results come from `DecompileAt.java` and `FindXrefs.java` on 29 October 2026.

## The source

The idea and the byte come from RetroCux: [Enable-the-Search-function-on-iPod-Video-5th-Gen](https://github.com/RetroCux/Enable-the-Search-function-on-iPod-Video-5th-Gen) (MIT license). The script `patch.py` of that project changes one byte of osos 1.3 at offset 0x130b50 from 0 to 1. RetroCux tested the change on a real 5G with 60 GB.

The project gives the SHA-1 `3281abc9f44bb8ddfa4e00da03488308fe624c53` for the osos 1.3. The osos of `iPod_25.1.3.ipsw` has the SHA-1 `d4415d7b40863e6a474a5393430703f893c3db15` (SHA-256 `784ae3d5…`). The research did not find the cause of the difference. At offset 0x130b50, both images have the same instruction. The `expect` value of the patch makes sure of the byte.

## The gate

`0x130b30` returns 0 on a 5G and 1 on a 5.5G:

```c
undefined4 FUN_00130b30(void)
{
  uint rev = thunk_FUN_00265164();
  if ((rev >> 16 == 0xb) && ((rev & 0xffff) < 0x11)) return 0;
  return 1;
}
```

The instructions at the end:

| Offset | Bytes | Instruction |
|---|---|---|
| 0x130b48 | `0200001a` | `bne` (the model is not 0xb: return 1) |
| 0x130b4c | `110050e3` | `cmp r0, #0x11` |
| 0x130b50 | `0000a033` | `movcc r0, #0` |
| 0x130b54 | `1080bd38` | `ldmcc sp!, {r4, pc}` |

## What the gate reads

The gate reads the hardware version `HwVr`. It does not read the RAM size, the drive size or the model number. Ghidra confirmed the code on 31 October 2026.

1. `0x130b30` calls the thunk at 0x9b310, which jumps to `0x265164`.
2. `0x265164` keeps the word at 0x1081de40 + 0x28. The value 0x7fffffff means "no value yet".
3. If there is no value, `0x265164` calls `0x2827b8`. It reads + 0x84 of the object that `0x2827b8` gives, and keeps the word.
4. `0x2827b8` returns the pointer at 0x1081df80. In normal operation, this pointer is 0x108710dc, the firmware copy of the SysInfo block.

Thus the firmware reads the word one time. The word does not change until the next start.

## How the value gets into the firmware

Ghidra gave steps 3 to 6 on 31 October 2026. Steps 1 and 2 come from the emulator research.

1. The boot loader reads the `HwVr` record from the `SysCfg` page of the NOR flash. It writes the value to `sysinfo + 0x84` at 0x40006df8.
2. The boot loader puts the tag 'SysI' at 0x4001ff18 and the block pointer at 0x4001ff1c.
3. `0x13bc`, called at 0x278, reads the tag and the pointer. It keeps the pointer at 0x40006000 + 0x8c.
4. `0x1658`, called at 0x2b8, copies 0x90 bytes from 0x40006000 to 0x14983060. Thus the pointer is now at 0x149830ec.
5. `0x281224`, called at 0x2bc, reads the pointer. It reads the length at + 4 and limits it to 0xf8. It copies the block to 0x108710dc with `0x7cae0`, and keeps the length at 0x1081dab4.
6. `0x281224` ends with a jump to `0x282800`. That function writes 0x108710dc to the pointer at 0x1081df80.

The default 0x10882048 of `0x2827b8` is only a fallback. It applies if the pointer stays 0, for example if there is no 'SysI' tag.

Thus `HwVr` and the RAM size come from one block. `HwVr` is at + 0x84 and the RAM size is at + 0xe0. The device information object of [volume-limit.md](volume-limit.md) is the same block.

Emulator measurement (31 October 2026, cold start, a copy of the iPodFirm profile, 1.5 billion instructions):

| Address | Value | Meaning |
|---|---|---|
| 0x4001ff18 | 0x53797349 | The tag 'SysI' |
| 0x149830ec | 0x40015898 | The pointer to the block of the boot loader |
| 0x1081df80 | 0x108710dc | The pointer that `0x2827b8` returns |
| 0x108710dc | 0x53797349 | The first word of the copy |
| 0x10871160 | 0x000b0010 | + 0x84: `HwVr` |
| 0x108711bc | 0x04000000 | + 0xe0: the RAM size, 64 MB |
| 0x1081de68 | 0x000b0010 | The word that `0x265164` keeps |
| 0x1081dab4 | 0x000000f8 | The copied length |
| 0x10882048 | 0x00000000 | The fallback object, not used |

| `HwVr` | iPod | Source | Search |
|---|---|---|---|
| 0x000b0005 | 5G (MA146) | Measured: NOR dump | No |
| 0x000b0010 | 5G, in the iPodLinux table | Published, not measured | No |
| 0x000b0011 | 5.5G | Measured: NOR of a retail 5.5G, 23 September 2026 | Yes |

The 16 high bits are the generation (0xb is the iPod Video). The 16 low bits are the board revision. A different NOR flash or logic board changes the result. A different drive or a different size of RAM does not change it.

Other functions use the same word. Refer to the entry for 0x265164 in [firmware-functions.md](../docs/firmware-functions.md).

## The callers

`FindXrefs.java` and `DecompileAt.java` found two callers. Both are for Search only.

| Caller | What it does with the result |
|---|---|
| 0x105a04 (case label 0x5f8b) | The main menu mask bit 0x10000000 for Search. With 0, Settings > Main Menu has no Search item. |
| 0x130ca4 (call at 0x130cd0) | Builds the Music menu (0x7600). With 1, it adds the two Search items (0x1526ac). It then makes the task `SearchHelperThread` (0x155e7c). |

## The change

| At | Expect | Value | Instruction after the change |
|---|---|---|---|
| 0x130b50 | `00` | `01` | `movcc r0, #1` |

Thus `0x130b30` always returns 1. On a 5.5G, the result was already 1. Thus the patch changes nothing on a 5.5G. The patch does not need to know the model.

No other patch changes 0x130b30–0x130b57. The patches that hook `0x105a04` change only its first instruction.

## The model in the app

iPodFirm reads the model code from the osos directory entry (0xB0). The 5G and the 5.5G have the same code. Thus the app cannot see the difference from the firmware.

Other sources:

- `iPod_Control/Device/SysInfo` on the data partition. The file can have `ModelNumStr`, `boardHwRev` and `pszSerialNumber`. On the iPod of the owner (29 October 2026), the file has 0 bytes. Thus this source is not always available.
- `SysInfoExtended` from SCSI INQUIRY pages. macOS gives no simple access to these pages for a mounted disk.
- The drive size: 60 GB is only a 5G, 80 GB is only a 5.5G, 30 GB is both. A flash card changes the size.

## Test status

- Byte check: the Apple osos 1.3 has `00` at 0x130b50 (29 October 2026).
- Emulator: not tested. The iPodFirm profile (`nor_model` A444) has `HwVr` 0x000b0010 (measured, 31 October 2026). This value is below 0x11, so the gate returns 0 on stock firmware. The earlier statement that this profile shows Search with no patch does not agree. Examine the screen to find the cause.
- Real iPod 5G: tested by RetroCux with their script. Not tested with iPodFirm.
