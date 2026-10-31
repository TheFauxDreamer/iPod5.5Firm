# Now Playing: what opens the screen

Status (31 October 2026): the patch `no-now-playing-timer` has the change. The owner tested version 0.1 in the emulator with the Split themes and reported that it works well. It is not tested on a real iPod.

The owner wants Now Playing to open only in 2 cases:

- The owner presses Play on a song.
- The owner selects the Now Playing menu item.

## The script format

Static. [tcmd-dump.py](tcmd-dump.py) disassembles `TCmd` 9088. It decodes 1,064 of the 1,065 functions, and each jump stays in its function. The other function, ID 0x53, is the top level of the script. It has a different layout.

| Offset | Content |
|---|---|
| 0x0 | u32: 0x13e5. u16 pair: 0, 0xe4. |
| 0x8 | The number table: 0xe4 u32 values. |
| 0x3bc | The offsets of the functions: 1,065 u32 values. |
| 0x1460 | The functions. Each has a header of 10 bytes: u16 ID, u16 arguments, u16, u16 variables, u16 code length. |

The function IDs start at 0xf79. Each ID is also the atom of the function, so `name 0x1094` refers to function 0x1094.

Names of the global methods (object 0x1392). These names come from the use in the script:

| Method | Function |
|---|---|
| 0x75 | Runs a function after a time in ms. |
| 0x76 | Cancels that timer. |
| 0x7c | Binds a key to a function. |
| 0x7f, 0x83 | Register a function for an event. |
| 0x89 | Pushes a screen. |
| 0x8a | Gets the current screen. |
| 0x92 | Tells if a screen is in the stack. |
| 0x93 | Tells if a screen is the current screen. |

## How Now Playing opens

Static.

- Function 0x1094 builds the Now Playing screen. It is View 0x5fce. The script refers to it 27 times. 21 of these only ask if it is the current screen.
- Function 0x1095 is "go to Now Playing". If the screen is in the stack, it goes back to it. If not, it pushes it.
- Function 0x1028 also pushes the screen. It is an event handler. Its event is not known.
- Function 0x12f4 is a second Now Playing screen, for video. Function 0x12f2 pushes it.

The timers in 0x109e, 0x10a6 and 0x10b1 do not open Now Playing. They operate only when the screen is already current.

## The callers of 0x1095

| Caller | Condition | Probable use | Status |
|---|---|---|---|
| 0x1030, 0x1051, 0x105b, 0x106d, 0x1073 | 0x13a4.0x115 starts play | Play from a list | Static. Keep. |
| 0x1065 | 0x13a4.0x116 starts play | Play from a list | Static. Keep. |
| 0xfe2, 0xfe3 | Start of play, or none | Not known | Static |
| 0xfe4 | None | Possibly the menu item | Not proved |
| 0x11b3, 0x11b4 | After 0x13c8.0x1e4 | Not known | Static |
| 0x1096 | Event 0x42800008 | Play message from the firmware | Static. The candidate. |

## The automatic open

The owner reported that Now Playing opens after 10 seconds with no input. The chain is in the script (Static):

1. 0x1007 registers the input handler 0x1005 (0x13a3.0xfb), and starts the timer with 0x1008.
2. 0x1005 runs at input, and starts the timer again.
3. 0x1008 runs 0x100a after the time in variable 0x13a7. The default is 10,000 ms. 0xfcc and 0x10df set it to 2,000 ms one time.
4. 0x100a calls 0xf84.
5. 0xf84: if 0x13a4.0x13a is true, and `name 0x98` gives true, and 0x1099 is false, it calls 0x1096. If 0x1099 is true, it calls 0x10b4. If `name 0x98` gives false, it calls 0x1007.
6. 0x1096 calls 0x1095, which opens Now Playing.

0x1094, which builds Now Playing, calls 0x1006. This stops the timer.

An earlier version of this note said that no timer opens Now Playing. This was wrong.

The firmware event 0x42800008 also reaches 0x1096. It is a different path. Its meaning is not proved: 0x1e0084, flag 0x40, type 8.

## Smallest change

Change 1 byte in 0xf84, at script offset 0x1a1c (osos 0x4b5e38): 0x07 in place of 0x96. This changes the call from 0x1096 to 0x1007. Then the timer starts again, as it does for the other case in the same function. The event path and Play from a list stay.

Status: the owner tested it in the emulator. It is not tested on a real iPod. Refer to [emulator.md](emulator.md).

## The timer cycle with the patch

The emulator recorded each native call at 0x120bec during idle playback, on the main menu, with version 0.2 of the byte change (31 October 2026). Three cycles had the same 30 calls. Each cycle ran approximately 342,000 instructions, from the first call to the last call. This is approximately 4.6 ms of one core in each 10 s.

| Script method | Native | Result | Status |
|---|---|---|---|
| 0x13a4.0x13a | 0x1e798c | The player state from 0x9ba00 is 1. It is true during playback. A test with Pause was not made. | Static, Emulator |
| 0x13de.0x25c | 0x22c500 | Reads the switch byte 0x1081dfdc. | Static, Emulator |
| 0x13df.0x2c4 | 0x12d890 | Reads + 0xd4 of the object. 0x1d81cc uses it to find an active modal screen. | Static, Emulator |
| 0x13dd.0x256 | 0x18145c | Reads + 0x38 of the object. The meaning is not known. | Static, Emulator |
| 0x1392.0x92 | 0x1d2d90 | Tells if a screen is in the stack. | Emulator |
| 0x1392.0x93 | 0x1d2d80 | Tells if a screen is the current screen. | Emulator |
| 0x13b3.0x199 | 0x156ec4 | Reads a value: arguments 0x6005 and 0x6000. | Static, Emulator |
| 0x13a3.0xfb | 0x1d8cb0 | `str r1, [r0, #0x118]`. It stores the handler in one field. | Static, Emulator |
| 0x1392.0x75 | 0x1d2778 | Starts a timer: time, key. | Static, Emulator |
| 0x13d5.0x2b5 | 0x248138 | Object + 0x174 is 2. | Static, Emulator |

The order of the native calls gives the three rows 0x25c, 0x2c4 and 0x256. The order agrees with the script.

## Answers to the open questions

**The input handler cannot accumulate.** 0x1d8cb0 stores one word. A second call replaces the first value.

**The timers cannot accumulate.** 0x1d2778 first calls vtable + 0xa4 (0x1d2524). 0x1d2524 finds the old timer by its key, removes it from the map at + 0xb4, and calls its method + 4, which is probably the delete. Then 0x1d2778 allocates a new timer of 0x30 bytes. The stock firmware runs the same path at each input.

**`name 0x98` tells if the firmware can interrupt the screen.** It gives false if a modal or another state in 0xf83 or 0x13dd.0x256 is active, or if one of 24 listed screens is in the stack or is current. 0xf84 then calls 0x1007. Thus the stock firmware already runs the same 10 s loop while one of these screens is open during playback. The patch makes the main path the same as this path.

**The second action of 0x1096 is for video.** If 0x13d5.0x2b5 is true, 0x1096 calls 0x12b2 and not 0x1095. 0x12b2 pushes the video Now Playing screen 0x12f4 with 0x12f2. Thus object + 0x174 = 2 is probably a video mode. This meaning comes from the script, and no video test was made. With the patch, the video Now Playing screen also does not open by itself. The video path does not operate on the owner's iPod (refer to [video-player.md](video-player.md)).

**0x1099 does not change.** It compares the value from 0x13b3.0x199 with 0x602e. The path to 0x10b4 can still call 0x1096. This path needs that value, and the meaning of the value is not known.

## Next steps

1. Test the 1 byte on a real iPod.
2. Identify 0xfe2–0xfe4, 0x11b3, 0x11b4 and the event of 0x1028.
3. Find the meaning of 0x18145c, the switch byte 0x1081dfdc and the value 0x602e.
