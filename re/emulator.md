# Testing customised firmware in the 5.5G emulator

[siggifly/ipod-emulator](https://github.com/siggifly/ipod-emulator) boots Apple's retail Video firmware from the reset vector. It has an LCD, a click wheel and ATA, but no audio or USB, and runs at about ¼ speed. Use it to check that a customised `osos` boots and shows your changes **before** flashing a real iPod.

## Easiest: iPodFirm's Emulator pane

1. **Install Emulator** builds [siggifly/ipod-emulator](https://github.com/siggifly/ipod-emulator) from source and installs `/Applications/ipod-emulator.app`. It installs Rust into your home folder if needed. The prebuilt v0.4.0 release can't be used, because it needs a dump of your iPod's boot ROM, while the current source synthesises one.
2. **Run in Emulator** does three things:
   - puts your edited OS into Apple's 1.3 firmware and builds a drive with the emulator's own `ipod-boot make-disk`;
   - boots it from cold in a **private profile** (`IPOD_EMULATOR_DATA=~/Library/Application Support/iPodFirm/EmulatorProfile`), so your own emulator devices are never touched;
   - runs it **headless with `--control=SOCKET`**, so iPodFirm can show the live screen (`shot`) and drive the buttons and wheel (`press`, `wheel`).
3. **Open Test iPod in the Emulator Window** opens the same test device in the emulator's own window, if you prefer that.

Notes from testing RetailOS 1.3:
- A fresh drive boots to the Language screen first.
- About six wheel detents move the highlight one row.
- String −4 ("iPod") is the main menu title.

## Manually: the emulator app

1. Download a [release](https://github.com/siggifly/ipod-emulator/releases) and open `ipod-emulator.app`. It isn't code-signed, so allow it under System Settings → Privacy & Security.
2. Build a custom `.ipsw`:
   ```sh
   uv run ipodfw pack-ipsw iPod_25.1.3.ipsw custom.bin -o custom.ipsw
   ```
3. Drop `custom.ipsw` onto the emulator window. It builds a drive from it and boots.

## Command line (needs a Rust toolchain)

```sh
cargo install --git https://github.com/siggifly/ipod-emulator ipod-gui ipod-machine eapp-inspect
# or clone and `cargo build --release`, which provides tools/ipod-boot
ipod-boot make-disk custom.ipsw disk.img     # drive with the custom firmware partition
RECIPE=... ipod-film run --out=_film         # one PNG per distinct screen + timing in frames.tsv
```

`frames.tsv` records when each screen appeared. That makes it the starting point for measuring the Play → Now Playing delay (Phase B in FEASIBILITY.md). Pin `FLASH=`, `DISK=` and `BUDGET=` when comparing a stock run against a patched one; see the emulator's `docs/DEVELOPING.md`.

## Caveats

- The emulator synthesises the boot ROM unless you give it a real 1 MB NOR dump, so a passing boot there is strong evidence but not proof.
- It has no USB, so `ipodfw flash` itself can only be tested on hardware.

## iPodFirm additions to the emulator

The patch `mac/Resources/emulator-patches/0001-ipodfirm-instrumentation.patch` adds these settings. Set them as environment variables when you start the emulator.

| Variable | Function |
|---|---|
| `IPODFW_PROFILE=1` | Counts the instructions in each 64-byte block of code. Read the counts with the `hist` command. |
| `IPODFW_REGS_AT=ADDR,COUNT` | Records the registers the first COUNT times ADDR runs. Read them with the `regs` command. |
| `IPODFW_TRACE_PC=FROM-TO` | Records the program counter in a range. |
| `IPODFW_WATCH_RANGE=BASE:LEN` | Records each CPU write into a range. Read the result with the `writes` command. Use the CPU address (osos offset), not the physical address. |
| (always on) | Records each write to the ATA taskfile (0xC30001E0–0xC30001FF), the ATA control register (0xC30003F8) and `GPO32_VAL` (0x70000080), with the instruction count, the emulated µs and the PC. Read and clear the log with the `evlog` command. Each `IPODFW_REGS_AT` record also adds a marker (address 0xFFFFFFFF) to this log. Writes to `GPO32_VAL` show only when `IPODFW_WATCH_RANGE` is set, for example `0x70000080:8`. |
| `IPODFW_RESET_AFTER=N` | Restarts the emulated iPod when the firmware writes 4 to `DEV_RS` (0x60006004), after N instructions. |

The instruction count stops while the emulated iPod sleeps. Thus, use the emulated µs in the `evlog` output to measure time, not the instruction count.

`peek` reads a physical address: use 0x10000000 + the osos offset.

CAUTION: The emulated start writes 4 to `DEV_RS` several times (start checks that pass on the hardware). Thus set `IPODFW_RESET_AFTER` to a value after the start, for example 1000000000.
