# Loading osos into Ghidra

```sh
uv run ipodfw extract iPod_25.1.3.ipsw -o fw13.bin
uv run ipodfw info -r fw13.bin          # osos: devOffset 0x4800, len 0x736000, image base 2048
uv run python -c "from ipodfw.partition import FirmwarePartition as F; open('osos.bin','wb').write(F(open('fw13.bin','rb').read()).image('osos'))"
```

Import `osos.bin` as **Raw Binary**:

| Setting | Value |
|---|---|
| Language | `ARM:LE:32:v4t` (ARM7TDMI; ARM and Thumb) |
| Base address | `0x10000000` (the `addr` field of the osos entry; SDRAM on the PP5022) |
| Entry | offset 0, vector table (`b` at 0x0; the "portalplayer" banner at 0x20) |

Useful anchors:

- **Resource blocks.** `ipodfw info -r` prints their offsets. Add `0x10000000` for the runtime address. The main block (BMap/Str/View/Menu) is at osos+0x331da0 in 1.3. Code that indexes these tables by resource id is the UI layer.
- **Strings.** The English block is `work/strings/block24_main.json` after `ipodfw unpack`. Search for the string *ids* as immediate constants to find the screens that use them, for example the ids of "Albums" and "Now Playing".
- **iPodWizard's volume-cap pattern** (`08 00 9F E5 94 00 90 E5`, then a `01 00`/`00 01` flag) shows what a one-constant behaviour patch looks like on 5G firmware. In 1.3 the pattern occurs at osos+0x9f0f8, but it is followed by `06 00`. The old hack therefore does **not** apply as-is; disassemble before changing anything there.

The emulator project also has a headless Ghidra/MCP setup (`ipod-boot ghidra serve`, `ipod-boot ghidra q xref|fn|dec`). See its `tools/ghidra/README.md`. That pairs static "who could call this" with dynamic "who did" traces.
