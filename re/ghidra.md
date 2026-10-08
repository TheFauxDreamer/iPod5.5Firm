# Load osos into Ghidra

This note tells how to load the osos image of firmware 1.3 into Ghidra. [docs/ghidra-guide.md](../docs/ghidra-guide.md) is the full guide: the scripts, the search recipes and the port procedure. [docs/firmware-functions.md](../docs/firmware-functions.md) gives the results.

## Get the osos image

```sh
uv run ipodfw extract iPod_25.1.3.ipsw -o fw13.bin
uv run ipodfw info -r fw13.bin          # osos: devOffset 0x4800, len 0x736000, image base 2048
uv run python -c "from ipodfw.partition import FirmwarePartition as F; open('osos.bin','wb').write(F(open('fw13.bin','rb').read()).image('osos'))"
```

CAUTION: Do not commit `fw13.bin` or `osos.bin`. They contain Apple code.

## Import settings

Import `osos.bin` as "Raw Binary" with these settings:

| Setting | Value |
|---|---|
| Language | `ARM:LE:32:v4t` (ARM7TDMI, ARM state and Thumb state) |
| Base address | `0x0` |
| Entry | Offset 0, the vector table (`b` at 0x0, the text "portalplayer" at 0x20) |

With the base address 0x0, a Ghidra address is equal to the osos offset and to the patch address. The project `osos13` of this research uses 0x0.

An earlier version of this note used the base address 0x10000000. This is the physical SDRAM address (the `addr` field of the osos entry). With that base, add 0x10000000 to each address in the documents. The emulator `peek` command uses the physical address.

## Useful anchors

- **Resource blocks.** `ipodfw info -r` shows their offsets. The main block (BMap, Str, View, Menu) is at osos 0x331da0 in 1.3. Code that finds items in these tables by resource ID is a part of the user interface layer.
- **Strings.** After `ipodfw unpack`, the English block is `work/strings/block24_main.json`. Search for a string ID as an immediate constant to find the screens that use it. Examples are the IDs of "Albums" and "Now Playing".
- **The volume limit pattern of iPodWizard.** The pattern `08 00 9F E5 94 00 90 E5`, then a flag `01 00` or `00 01`, is a one-constant patch on 5G firmware. In 1.3 the pattern occurs two times. At 0x9f0f8 the bytes after it are `06 00`, and iPodWizard skips this match. At 0xa0348 the bytes after it are `01 00`. This is the EU volume limit. Refer to [volume-limit.md](volume-limit.md).

## The Ghidra server of the emulator project

The emulator project also has a Ghidra set-up without a window (`ipod-boot ghidra serve`, `ipod-boot ghidra q xref|fn|dec`). Refer to its `tools/ghidra/README.md`. It connects the static callers ("which code can call this") with the dynamic traces ("which code called this").
