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

## The candidate for the automatic open

Static, with Ghidra for 0x1e0084. The bulk decompile does not have this code.

1. 0x1e0084, method of vtable 0x670820 (slot at 0x670820) receives a message. Byte 0 is the type. The word at + 0x10 has flags.
2. With flag 0x40 and type 8, it calls 0x1d09fc(object, 1). This sends 0x42800008. Types 7 and 10 send 0x42800009.
3. 0x19a1dc forwards 0x42800008 to the script with 0x1d32e0.
4. The script function 0xfd1 registers 0x1096 for this event.
5. 0x1096 calls 0x1095, unless 0x13d5.0x2b5 is true. Then it calls 0x12b2.

Not proved: that type 8 means that play starts, and when the firmware sends it. Also, type 8 sets the sleep state with 0x184860, and 7 and 10 clear it with 0x18482c. This agrees with a start and a stop of play.

The evidence does not show a timer that opens Now Playing.

## Smallest change, if the test agrees

Change 2 bytes in 0x1096, at script offset 0x7255 (osos 0x4bb671): `true`, `return` in place of `name 0x1095`. The function then returns and does not open Now Playing. A `bytes` patch can do this, with `"size": 0`.

Play from a list uses its own calls to 0x1095, so that path stays.

Risks:

- The Play button outside a list possibly no longer opens Now Playing.
- The Now Playing menu item is not identified.
- Handler 0x1028 can also open the screen.

## Next steps

1. The owner tells when the automatic open occurs: at the end of a song, after a time, or with the Play button.
2. Identify 0xfe2–0xfe4, 0x11b3, 0x11b4 and the event of 0x1028.
3. Make a test firmware with the 2 bytes.
