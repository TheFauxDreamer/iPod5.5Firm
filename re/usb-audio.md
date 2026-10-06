# USB audio in osos 1.3

## Goal

The owner has a USB-C mod and no MFi DAC. The goal is that the iPod is a USB sound card (USB Audio Class 1) for a Mac or a phone. [rockpod](https://github.com/nuxcodes/rockpod) has a similar function on the iPod Classic, but its code is for Rockbox and a different CPU.

## Result

The Apple firmware 1.3 for the 5.5G already contains a USB Audio Class 1 source: the iPod sends audio to the USB host on endpoint 0x81 (isochronous IN). Apple used it for accessories that take digital audio from the iPod over USB, for example the Wadia 170iTransport.

The stock firmware sends the audio to USB only after an iAP accessory sends the "Digital Audio" lingo (0x0A) commands. A Mac does not send iAP commands. Thus a patch must remove this condition. Apple's USB code itself can stay the same.

## The USB audio driver

Offsets are osos file offsets. The CPU address is the same.

| Offset | Function |
|---|---|
| 0x24d628 | Makes the composite USB device "iPod USB Interface". It adds four interface objects: the disk (mass storage), 0x1de818 (probably HID for iAP), the audio control object (vtable 0x666920) and the audio streaming object (0x132614). |
| 0x170f2c | The USB task. It calls 0x24d628 and 0xd85d8, then waits for USB events. |
| 0xd85d8 | Sets the device descriptor values: vendor 0x05AC, the product ID of the model (0x1209 for the 5.5G), "Apple" and "iPod". The descriptors are made at run time. They are not in the image as bytes. |
| 0x132614 | Makes the audio streaming object (vtable 0x666958). It sets the object pointer at state + 0x10, and this starts `USBAudioTask`. |
| 0xc75cc | `USBAudioTask`. It waits for the object, then calls 0x13231c and 0x132038 in a loop. |
| 0x132038 | The stream loop. It uses two sets of 12 packets, one after the other. It gets each packet from the audio ring (0x1e3064) and sends the set to endpoint 0x81 (0x24d518). It stops when state + 2 is 0. |
| 0x10fbb4 | The packet size: sample rate × 4 bytes, for 1000 frames/s (full speed) or 8000 microframes/s (high speed), with a remainder for 44.1 kHz. |
| 0x1323d8 | Handles SET_INTERFACE (bRequest 0x0B). Alternate setting 1 starts the stream (0x132274). Alternate setting 0 stops it (0x13221c). |
| 0x1325b0 | Opens endpoint 0x81 as isochronous: 192 bytes per packet at full speed, 24 bytes at high speed (0xdad4c). |
| 0x13249c | Handles SET_CUR "sampling frequency" on the endpoint. It accepts 8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100 and 48000 Hz. It sets the sample-rate converter (0x1e2f60). |
| 0x132274, 0x13221c | Start and stop the stream: state + 2 = 1 or 0. The start also calls 0x1e6640 (audio route). |

State of the audio streaming object: RAM 0x108234ec. +1 rate code, +2 stream on, +4 USB device, +8 sample rate, +0x10 object, +0x18 event.

## The iAP condition

| Offset | Function |
|---|---|
| 0x1e5b84 | iAP lingo 0x0A ("Digital Audio") handler (table entry 0x670f00). Command 3 gives the sample rates of the accessory. The handler keeps the rates only if 32, 44.1 and 48 kHz are all in the list. The accessory must have lingo 0x0A in its identified lingoes (bit 0x400). |
| 0x1e61c0 | Returns 1 if the audio goes to USB. The conditions: the rate bits 0x1C0 are set (state + 0x0C), state + 0 and state + 1 are not 0, and the USB stream is on (0x132028). |
| 0x1e6184, 0x1e6640 | Call 0x1e61c0 and then switch the audio route (0x159818, 0x1a3070 + 0x59). |
| 0x1e6208 | Returns 1 if the accessory accepts a given sample rate. |

Route state: RAM 0x1081ee48. +0 and +1 flags, +0x0C rate bits (bit 0 = 8 kHz … bit 8 = 48 kHz), +0x28 and +0x2C timers.

## The real iPod (2026-10-06)

The owner's iPod (1 TB flash, 2048-byte sectors) on the Mac: vendor 0x05AC, product 0x1209, `bNumConfigurations` = 2. macOS uses configuration 1, with interface 0 = mass storage (class 8, subclass 6, protocol 0x50). Configuration 2 is probably the "iPod USB Interface" with the audio interfaces.

## Open items before a patch

1. Read the full descriptors of configuration 2 from the real iPod. Connect the iPod with the USB-C mod and enter:

   ```sh
   system_profiler SPUSBDataType
   ioreg -p IOUSB -l -w0 | grep -A40 '"iPod"'
   ```

   Record the number of configurations and the interfaces in each configuration. The result tells if the Mac already sees the audio interfaces.
2. Find the meaning of the route flags state + 0 and state + 1 (0x1081ee48). Find the code that writes them.
3. Find what the iPod shows when the host selects the audio interface and not the disk ("Do not disconnect" or the normal menus).

## Proposed patch (after the open items)

- A setting "USB Mode: Disk / Audio" on the iPod, and a switch in the iPodFirm Patches pane.
- In "Audio" mode: 0x1e61c0 returns 1 if the USB stream is on (SET_INTERFACE alternate 1 from the Mac), with no iAP condition. The patch also sets the rate bits for 32, 44.1 and 48 kHz.
- If the Mac selects the disk interface first, the patch must hide the disk interface in "Audio" mode, so that the music continues to play.

The emulator has no USB. Thus all USB tests must be done on the real iPod. A defective USB patch cannot stop a restore, because the disk mode in the boot flash (Select+Play) does not use osos.
