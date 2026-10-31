# Music from USB-C and the headphone jack at the same time

This note is research only. It records an idea for a possible future exploration. No branch and no patch exist. Do not make the patch unless the owner asks.

## Context

The owner asked if the iPod can send music to USB-C headphones and to the 3.5 mm headphone jack at the same time (27 October 2026). The patch `usb-audio-out` 1.9 cannot do this. The firmware gives each decoder buffer to one output only.

## The current state

- 0x1a2d60 gives each decoder buffer to the USB source (0x1e2bc8) if the audio output object + 0x5a is 1. Else it gives the buffer to the codec driver (vtable + 0x18). Refer to [../docs/firmware-functions.md](../docs/firmware-functions.md) and [usb-host.md](usb-host.md).
- +0x5a is +0x58 (the USB stream is on, 0x1a2fa0) and +0x59 (the route is allowed, 0x1e6640).
- When USB-C Audio is On, `usb-audio-out` sets the two flags. Then the codec gets no buffers, and the headphone jack is silent.
- The USB source puts each buffer in a queue of 6 entries (0x1e2c90). After the fill, the patch gives the buffer back to the decoder (0xfed68).

## Is it possible?

Probably yes. A hook on 0x1a2d60 can give the same buffer to the USB source and to the codec driver. This analysis comes from the code that is already known. Ghidra did not examine the codec side for this idea.

These are the problems:

1. **The buffer give-back.** Each output gives the buffer back to the decoder (0xfed68). The patch must count the two users. It must give the buffer back one time only, after the second user.
2. **Two clocks.** The codec uses its I2S clock. The USB packets use the USB frame clock of the iPod (1 ms). The two clocks drift, probably by 50–100 ppm. After some minutes, one output gets too few or too many samples. The patch must add or remove one sample at times on the USB side. The patch already makes 44 or 45 frames in each packet, thus a small change is possible.
3. **The latency.** The USB ring is 24–40 ms in front of the USB frame. If one person hears the two outputs, that person hears an echo. For two listeners, this is not a problem.
4. **The volume.** The click wheel sets the codec volume and the USB volume (SET_CUR). The patch must keep the two volumes correct.
5. **The CPU.** The USB route uses about 15 % of core 0 (refer to [usb-host.md](usb-host.md)). The codec DMA adds a small load.
6. **The EQ.** The software EQ of 1.3 is in the decoder step 0x24ab48, before 0x1a2d60. Then the two outputs get the same EQ. Refer to [custom-eq.md](custom-eq.md).

## Possible steps

Do these steps only if the owner asks.

1. Make a branch `usb-dual-out` in a new worktree. Use a test app name, for example "iPodFirm Dual Out Test".
2. In Ghidra, read 0x1a2d60, the codec driver (vtable + 0x18) and 0xfed68. Record how the codec gives a buffer back. Write the result in [usb-host.md](usb-host.md), then in [../docs/firmware-functions.md](../docs/firmware-functions.md).
3. Add an option "Also Headphone Jack" to `usb-audio-out` in a new version. Use a hook on 0x1a2d60 and a reference count.
4. Add the drift correction in `hook_fill`.
5. Test in the emulator. Make sure that the two paths get buffers and that the decoder does not stop.
6. Test on the real iPod. Play music through the EarPods and the jack for 30 minutes. Listen for a stutter or a stop.
7. Update [../docs/safety.md](../docs/safety.md) and [../docs/modifications.md](../docs/modifications.md).
