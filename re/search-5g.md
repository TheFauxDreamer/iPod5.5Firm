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

`0x265164` returns a cached word from `0x2827b8` + 0x84. The 16 high bits are the model (0xb is the iPod Video). The 16 low bits are the revision. The emulator notes record `HwVr 0x000b0005` for a 5G (MA146). A prototype dump has `0x000b0011`, probably a 5.5G.

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
- Emulator: not tested. The emulator profile of iPodFirm is a 5.5G. The 5.5G shows Search with and without the patch.
- Real iPod 5G: tested by RetroCux with their script. Not tested with iPodFirm.
