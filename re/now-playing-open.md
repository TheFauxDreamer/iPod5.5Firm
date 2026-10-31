# Now Playing: what opens the screen

Status (31 October 2026): research only. There is no patch.

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

Status: not tested. The owner reported on 31 October 2026 that the emulator cannot test it, because it does not play music. The test needs a real iPod.

## Next steps

1. Test the 1 byte on a real iPod.
2. Identify 0xfe2–0xfe4, 0x11b3, 0x11b4 and the event of 0x1028.
3. Find what `name 0x98` and 0x13a4.0x13a test.
