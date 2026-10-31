# Test a changed firmware in the 5.5G emulator

[siggifly/ipod-emulator](https://github.com/siggifly/ipod-emulator) starts the Apple firmware of the iPod Video from the reset vector. It has an LCD, a click wheel and an ATA disk. It has no audio and no USB. It runs at approximately one quarter of the real speed. Use it to make sure that a changed osos starts and shows your changes before you flash a real iPod.

## Method 1: the Emulator pane of iPodFirm

1. Click "Install Emulator". The app builds [siggifly/ipod-emulator](https://github.com/siggifly/ipod-emulator) from source and installs `/Applications/ipod-emulator.app`. If Rust is not installed, the script installs it in your home folder.
2. Click "Run in Emulator". The app does these steps:
   - It puts your changed osos into the Apple firmware 1.3 and makes a drive with `ipod-boot make-disk`.
   - It starts the drive from cold in a private profile (`IPOD_EMULATOR_DATA=~/Library/Application Support/iPodFirm/EmulatorProfile`). Your own emulator devices do not change.
   - It runs the emulator without a window (`--control=SOCKET`). The app shows the screen (`shot`) and sends the buttons and the wheel (`press`, `wheel`).
3. To use the window of the emulator, click "Open Test iPod in the Emulator Window".

The prebuilt release v0.4.0 is not usable, because it needs a dump of the boot ROM of your iPod. The current source makes a synthetic boot ROM.

Results with RetailOS 1.3:

- A new drive starts at the Language screen.
- Approximately six wheel steps move the highlight one row.
- String −4 ("iPod") is the title of the main menu.

## Method 2: the emulator app

1. Download a [release](https://github.com/siggifly/ipod-emulator/releases) and open `ipod-emulator.app`. The app has no code signature. Allow it in System Settings > Privacy & Security.
2. Make a custom `.ipsw` file:

   ```sh
   uv run ipodfw pack-ipsw iPod_25.1.3.ipsw custom.bin -o custom.ipsw
   ```

3. Drag `custom.ipsw` onto the emulator window. The emulator adds the file to its list as an installer.

Caution: a drag does not change the current drive. The emulator can resume the stock firmware from its snapshot. Measured on 31 October 2026: `disk.0.installed` in `settings.txt` stayed "Apple's software". To run a custom firmware, use **Run in Emulator** in iPodFirm, or use Method 3 with a separate profile folder in `IPOD_EMULATOR_DATA`.

## Method 3: the command line (a Rust toolchain is necessary)

```sh
cargo install --git https://github.com/siggifly/ipod-emulator ipod-gui ipod-machine eapp-inspect
# or clone the repository and run `cargo build --release`, which gives tools/ipod-boot
ipod-boot make-disk custom.ipsw disk.img     # a drive with the custom firmware partition
RECIPE=... ipod-film run --out=_film         # one PNG for each different screen, and the times in frames.tsv
```

`frames.tsv` records the time of each screen. Use it to measure the time from Play to Now Playing. To compare a stock run with a patched run, set the same `FLASH=`, `DISK=` and `BUDGET=`. Refer to `docs/DEVELOPING.md` of the emulator.

## Limits

- The emulator makes a synthetic boot ROM unless you give it a real 1 MB NOR dump. Thus a correct start in the emulator is strong evidence, but not proof.
- The emulator has no USB. You can test `ipodfw flash` only on a real iPod.
- The emulator answers 0 for the counter at 0x60006038. Thus the shuffle seed is 0, and the shuffle is not random. Refer to [shuffle.md](shuffle.md#emulator-tests) for a test firmware with a fixed seed.
- The emulator keeps a restore point in its profile. A run with `--control` continues from it. Start the emulator with `--cold` to start from the drive.
- Music plays, but the emulator has no sound output. A song advances at approximately 0.65–0.72× of real time (measured on 31 October 2026 on an M2 Pro, with the test library). The menu stays at 1.00×. The song time moves, and the next song starts at the end of a song.
- The control socket measures `hold` and `sleep` in host time. When the emulator is slow, a hold of 900 ms can be a short push for the iPod, and a short push can arrive after the next input. Wait in emulated time (the instruction count, 75 M for each second) and make a hold longer when `realtime` is low. A push of 30 ms is a short push; a push of 120 ms or more at full speed can be a hold.
- Pause the music directly after the start (Play/Pause) before you test other screens. Then the emulator runs at full speed. The player has a play list and a current song while it is paused.
- A volume change on the Now Playing screen changed neither the samples nor the WM8758 registers 0x0b, 0x0c and 0x34–0x37 in the test of 31 October 2026. The cause is not known.

## The iPodFirm additions to the emulator

The patch `mac/Resources/emulator-patches/0001-ipodfirm-instrumentation.patch` adds these settings. Set them as environment variables when you start the emulator.

| Variable | Function |
|---|---|
| `IPODFW_PROFILE=1` | Counts the instructions in each 64-byte block of code. The `hist` command gives the counts. |
| `IPODFW_REGS_AT=ADDR,COUNT` | Records the registers the first COUNT times that ADDR runs. The `regs` command gives the records. |
| `IPODFW_TRACE_PC=FROM-TO` | Records the program counter in a range. |
| `IPODFW_WATCH_RANGE=BASE:LEN` | Records each CPU write into a range. The `writes` command gives the result. Use the CPU address (osos offset), not the physical address. |
| (always on) | Records each write to the ATA taskfile (0xC30001E0–0xC30001FF), the ATA control register (0xC30003F8) and `GPO32_VAL` (0x70000080), with the instruction count, the emulated µs and the PC. The `evlog` command gives the log and clears it. Each `IPODFW_REGS_AT` record also adds a marker (address 0xFFFFFFFF) to this log. The writes to `GPO32_VAL` show only when `IPODFW_WATCH_RANGE` is set, for example `0x70000080:8`. |
| `IPODFW_MARK_AT=ADDR,ADDR,...` | Adds a marker to the `evlog` output (address 0xFFFFFFFD, byte = index in the list) each time that one of the addresses runs. A button frame also adds a marker (address 0xFFFFFFFE, byte = buttons). The `evlog` also records writes to the I²C controller (0x7000C000–0x7000C0FF). |
| `IPODFW_RESET_AFTER=N` | Restarts the emulated iPod when the firmware writes 4 to `DEV_RS` (0x60006004), after N instructions. |

## The music playback fix

The patch `mac/Resources/emulator-patches/0002-ipodfirm-music-playback.patch` makes songs play. Before this patch, the song time stayed at 0:00. The patch makes two changes in `tools/ipod-machine/src/lib.rs`:

1. The COP gets its turn from `steps()`, not from `executed`. `executed` stops while the CPU sleeps. Thus the old test gave the COP 1000 instructions for each halted cycle, or no instructions for the full sleep.
2. `Machine::QUANTUM` is 50, not 1000.

The results of the song start, with change 1 in each test:

| Quantum | Songs that started |
|---|---|
| 10000 | 0 of 4 |
| 1000 | 1 of 4 |
| 50 | 9 of 9 |

The speed with a quantum of 50 is the same as the speed with 1000.

The firmware path that the tests measured:

1. The firmware sends silence on DMA channel 0x6000B000 to the I2S FIFO: 9216 bytes for each buffer, 4 or 5 buffers.
2. It stops this channel. It then sends the music on channel 0x6000B020: 4096 bytes for each buffer.
3. A failed start stops after step 1. The COP then waits at 0x29daa8 in a software lock between the cores, and later at 0x235310 in the queue wait 0x235250. The cause of the dependency on the quantum is not known.

A test recording of these FIFO words gave 277.18 Hz for T0004 and 246.94 Hz for T0002. These are the correct frequencies. A 30 s song gave 30 s of frames. The patch does not keep this recording.

The instruction count stops while the emulated iPod sleeps. Thus use the emulated µs in the `evlog` output to measure time, not the instruction count.

`peek` reads a physical address. Use 0x10000000 + the osos offset.

CAUTION: The emulated start writes 4 to `DEV_RS` several times. These writes are start checks that pass on the hardware. Thus set `IPODFW_RESET_AFTER` to a value after the start, for example 1000000000.

Only a build from `install-emulator.sh` has these additions. A release download does not have them. The script keeps its build in `~/Library/Application Support/iPodFirm/emulator-src/target/release/`.
