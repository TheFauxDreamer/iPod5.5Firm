# The power and the hardware of RetailOS 1.3

This note gives the research of the system "Power and the hardware" of the note
[firmware-systems.md](firmware-systems.md). The system has 9 named parts. The
parts are 8 tasks and the name `PowerManager`.

The note gives the tasks, the power manager, the registers of the power chip
and the clock.

The addresses are the offsets in the image of the osos. The CPU address of the
code is the offset plus 0x10000000. The note uses the offset.

> This note is the research of the decompilation project. The notes of the
> earlier research stay as they are. The note [sleep.md](sleep.md) gives the
> sleep, the note [backlight-timer.md](backlight-timer.md) gives the backlight
> and the note [piezo.md](piezo.md) gives the piezo.

## The summary

The power of the iPod comes from the power chip of the PP5020 of Apple. The
firmware has 3 parts.

1. The **power chip**. The chip has the clock, the timer, the real-time clock,
   the general purpose input and output pins and the pulse width modulator of
   the piezo.
2. The **tasks**. The tasks read the state of the hardware and give the state to
   the application.
3. The **power manager**. The manager gives the state of the power to the
   application.

The iPod Video has no modem. The task `CNATask` does nothing for the iPod
Video. The iPod has no real-time clock of its own. The task `RTCTimerMgr` uses
the clock of the system.

## The tasks of the system

The table of the tasks of the firmware is at 0x25d63c. The table has 21 tasks.
8 of the tasks belong to this system.

| The task | The method | The work |
|---|---|---|
| `BacklightTask` | 0x28453c | The backlight of the screen. |
| `WatchdogTask` | 0x2856f0 | The watchdog of the processor. |
| `HoldSwitchTask` | 0x284f30 | The switch of the hold. |
| `LowBattDebounceTask` | 0x284a18 | The filter of the state of the battery. |
| `RTCTimerMgr` | 0x285460 | The clock of the system. |
| `AlarmTask` | 0x284374 | The alarm of the system. |
| `PCFPowerMgr` | 0x284ff4 | The power of the computer. |
| `CNATask` | 0x284a54 | The network of the modem. The iPod has no modem. |

### The task of the clock of the system

The method 0x285460 is the task `RTCTimerMgr`. The method waits for the events
of the queue 0x88. Each event has a record of 0x14 bytes. The byte at +0xe of
the record says that the timer must run. The byte at +0xf says that the timer
must be reset. The word at +0x10 is the number of the ticks.

The method calls the function 0x120878 to read the time. The method calls the
function 0x113470 to wait for the next event. The method calls the function
0x102074 to give the time.

### The task of the power of the computer

The method 0x284ff4 is the task `PCFPowerMgr`. The method calls the function
0x2659cc. The method then calls the function 0xb65c0 and the function 0xb0520.
The method waits for the events of the queue with the function 0xa7a30.

The method calls the kernel with the number 0x18 at the end. The number 0x18 is
the call to the ThreadX that deletes the thread.

### The task of the network of the modem

The method 0x284a54 is the task `CNATask`. The method calls the function
0x1c7e4c. The method registers the object of the network. The iPod Video has no
modem. The method does nothing for the iPod Video.

### The task of the backlight

The method 0x28453c is the largest method of the system. The method reads the
state of the backlight with the function 0x265230. The method waits for the
events of the queue of the backlight.

| The event | The work |
|---|---|
| 0xa6 | The backlight goes on. The method reads the time of the timer 0x136 and sets the state to 1. |
| 0xa7 | The backlight goes off. The method calls the function 0x266288 with the value 0 and sets the state to 0. |
| 0xa8 | The backlight changes. The method calls the function 0x26617c and sets the state to 2. |
| 0xa9 | The backlight ticks. The method counts the ticks at +8 up to 30. |
| 0xaa | The backlight goes off after the change. The method calls the function 0x266288 with the value 0. |

The function 0x266288 sets the brightness. The function 0x26617c starts the
timer of the backlight. The function 0x283348 sets the state of the screen.
The method calls the function 0x283348 with the value 0 or with the value 1.

### The task of the watchdog

The method 0x2856f0 makes the task of the watchdog. The method calls the
function 0x1084 to read the tick of the system. The method then calls the
function of the table at 0x2857b8. The table holds the function that resets
the processor.

The method calls the software interrupt 0x123456 if the memory for the table
is not there. The string "watchdog: Could not allocate timer!" is at 0x28578c.
The string "watchdog: No registered handlers for " is at 0x2857bc.

### The task of the switch of the hold

The method 0x284f30 reads the state of the switch with the function 0x2651dc.
The method then calls the function 0x1893a4 with the state. The method
registers the object of the state.

### The task of the alarm

The method 0x284374 waits for the events of the queue of the alarm. The events
are the numbers 0x89, 0x8a, 0x8b and 0x94.

| The event | The work |
|---|---|
| 0x89 | The alarm rings. The method plays the tone 0xb4 and the tone 0x90 with the function 0xcd430. |
| 0x8a | The snooze of the alarm. The method waits 1000 ms with the function 0xa62b4 and calls the function 0x91438. |
| 0x8b | The alarm stops. The method sends the notification 7. |
| 0x94 | The alarm is set. The method calls the function 0x211d20 and the function 0x213c5c. |

The function 0xcd430 is the piezo. The note [piezo.md](piezo.md) has the 8
functions of the piezo.

## The manager of the power

The name `PowerManager` is at the image 0x14815c. The function 0x148108 uses
the name. The function makes the object of the manager and registers it.

The manager gives the state of the power to the application. The state has the
values in the byte at +0x1c of the object. The function 0x197e70 of the import
of the pictures uses the same byte for the state of the import.
## The registers of the power chip

The power chip has 4 groups of registers. The addresses are in the tables of the
image.

### The general purpose input and output pins

The table of the pins is at the image 0x281f00. The table has 5 addresses.

| The word | The register |
|---|---|
| +0x00 | 0x6000D000 |
| +0x04 | 0x6000D080 |
| +0x08 | 0x6000D0EC |
| +0x0C | 0x6000D100 |
| +0x10 | 0x6000D154 |

The function 0x281b4c fills the table. The function takes the state of the pins
and the state of the direction of the pins. The function is called by the
function 0x2823bc and the function 0xb43dc.

The function 0x281b4c also writes the registers 0x70000080, 0x70000084 and
0x7000008c. The function writes the state of the pins in these registers.

### The power management unit

The function 0x1b73c8 makes the object of the power management unit. The object
has the address 0x70000034 at +8 and the address 0x60006020 at +4. The function
sets the bit 0x40000000 of the word at 0x1b741c. The word at 0x1b741c holds
the address 0x70000020.

### The clock and the timer

The table of the clock is at the image 0x1fcf50. The table has 11 addresses.
The function at 0x1fca88 copies the table into the registers.

| The word | The register |
|---|---|
| +0x00 | 0x60004000 |
| +0x04 | 0x60004008 |
| +0x08 | 0x60004010 |
| +0x0C | 0x60004014 |
| +0x10 | 0x60004018 |
| +0x14 | 0x6000401C |
| +0x18 | 0x60004020 |
| +0x1C | 0x60004024 |
| +0x20 | 0x60004028 |
| +0x24 | 0x6000402C |
| +0x28 | 0x60004030 |

The word at 0x11b4 holds the address 0x60004028. The word at 0x11b8 holds
the address 0x60004038.

The function 0x1c7f58 makes the object of the clock. The object has the
address 0x70000020 at +0xc. The function 0x1c7f58 uses the address 0x70000080
if the word at 0x1c7f98 is 0x3230.

The timer of the microseconds is at 0x60005010. The function 0xded04 reads it.

### The state of the battery

> Correction (31 October 2026): the value of the function 0x265164 is not a
> battery measurement. It is the hardware version `HwVr`. The 16 high bits are
> the generation of the iPod. The 16 low bits are the board revision. The word
> does not change until the next start. Thus the functions in this section
> select an action from the iPod generation. "Channel" in this section means
> the generation. Refer to [search-5g.md](search-5g.md#what-the-gate-reads).
> The names "battery", "charger" and "power" of these functions are not proved.

The function 0x265164 reads the value. The function keeps the word at
0x1081de40 + 0x28. The word is 0x7fffffff when the value is not yet there. The
function then reads + 0x84 of the object that the function 0x2827b8 gives.

The function 0x265a74 says that the battery is low. The function gives 1 when
the 16 high bits of the value are 10, 11 or 12. The function gives 0 for the
other numbers. The task `LowBattDebounceTask` has the method 0x284a18. The
method calls the function 0x265a74. The method then calls the function
0x22ec90 and the function 0x163ffc.

The function 0x265820 gives the state of the charger. The function gives 1 when
the 16 high bits of the value are 5, 6, 8 or 9. The function 0x2657fc gives
the state of the power. The function gives 1 when the 16 high bits of the value
are 10, 11 or 12.

The function 0x264fa4 gives the state of the power. The function has a switch
with the cases 4 to 0xc. The function reads the value with the function
0x265164. The function reads the pins of the charger with the function
0x282b70. The function puts the state in the byte at +6 of the object at the
image 0x65160. The states are the numbers 8, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf,
0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16 and 0x17. The function 0x264fa4
sets the states 0xb, 0xc, 0xd, 0xe, 0xf, 0x10, 0x11, 0x12, 0x13, 0x14 and
0x15.

The function 0x265abc gives the state of the audio. The function has a switch
with the cases 4, 5, 6, 7, 8, 9, 0xa, 0xb and 0xc. The function gives 0 when
the 16 high bits of the value are not in this list.

The function 0x2823bc starts the driver of the general purpose input and
output. The function reads the value with the function 0x265164. The function
uses the 16 high bits of the value to select the state of the pins. The
function has a switch with the cases 4, 5, 6, 9, 10, 0xb and 0xc.

The function 0x175818 reads the state of the battery. The function reads the
word at +0x84 of the object of the driver. The function has a switch with the
cases 4 to 0xc. The function puts the state of the battery in the word at
+0x1bc of the object and the state of the charger in the word at +0x1be.

> The research did not find the register of the converter. The research found
> the chain of the functions. The research did not find the function that
> writes the word at +0x84 of the object of the driver. The research did not
> find the interrupt of the converter.

### The pulse width modulator

The pulse width modulator is at 0x7000A000. The function 0xc719c writes the
period of the tone. The function 0x11c750 writes 0 to the register when the
buffer of the tones is empty. The note [piezo.md](piezo.md) has the 8
functions of the piezo.

## The limits of the research

| The limit | The result |
|---|---|
| The names of the registers of the power chip | The research found the addresses of the registers. The names of the registers come from the manual of the PP5020. The research did not find the names in the image. |
| The state of the battery | The task `LowBattDebounceTask` has the method 0x284a18. The research did not find the register that gives the state of the battery. |
| The task `CNATask` | The method 0x284a54 is the task of the modem of the older iPod. The iPod Video has no modem. The research did not trace the task. |
| The task `PCFPowerMgr` | The method 0x284ff4 is the power of the computer. The research did not trace the task. |
| The task `RTCTimerMgr` | The method 0x285460 is the clock of the system. The research did not trace the task. |
| The state of the power | The function 0x197e70 of the import of the pictures reads the byte at +0x1c of the object of the import. The research did not find the function that sets the byte for the power. |

## The sources

- The image of the osos: `~/Library/Application Support/iPodFirm/re/osos-1.3.bin`
- The decompiler: Ghidra 12.1.4, with the script `DecompileAt.java` of the folder [ghidra-scripts](ghidra-scripts)
- The note of the sleep: [sleep.md](sleep.md)
- The note of the backlight: [backlight-timer.md](backlight-timer.md)
- The note of the piezo: [piezo.md](piezo.md)
