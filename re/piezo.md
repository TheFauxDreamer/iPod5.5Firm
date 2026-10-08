# The piezo in osos 1.3

The iPod Video has a piezo speaker for the clicks and the beeps. This note gives the firmware path from `tone` to the hardware. Offsets are osos file offsets. The CPU address is the same. The results come from Ghidra (project osos13, `DecompileAt.java`, `FindConstant.java`) on 2026-10-08.

## The path

1. `tone(value, microseconds)` (0xcd430) sends a type-0 message to the queue 0x15 and waits for the answer (0xa6540, 0xa6770). The message has the value at +0x14 and the duration at +0x18. The function returns the word at +0x1c: 0 if the note is in the queue, 1 if the queue was full.
2. The piezo task `AsyncPiezo` (0x285060) receives the message. It puts the value and the duration in a ring buffer of 16 entries (RAM 0x10882314: values; 0x10882354: durations). The read and write indexes are at RAM 0x1081dfb0. The buffer holds 15 notes. If it is full, the task sets the answer to 1, and the note is lost.
3. If no note plays, the task starts the player and records the time (`USEC_TIMER`, 0x60005010).
4. The player 0xc719c runs after each message wait. When the time of the current note is over, it takes the next entry (0xc9670 increments the index modulo 16). It writes `value | 0x80800000` to 0x7000a000 and `duration | 0x80000000` to the timer at 0x60005008.
5. When the time of a note is over and the buffer is empty, the player calls 0x11c750. This function writes 0 to 0x7000a000 (the piezo stops) and clears bit 31 of the timer at 0x60005008.

A message of type 1 empties the buffer (the read index gets the write index).

## The value

The value is a period, not a frequency. A larger value gives a lower tone. The firmware does not show the clock of the piezo PWM. Rockbox uses the same register (`PWM0_CTRL` at 0x7000a000) with the formula `91225 / Hz` (`piezo_hz` in `firmware/target/arm/ipod/piezo.c`). Thus:

    Hz = 91225 / value

| Value | Hz | Use in the firmware |
|---|---|---|
| 0xb4 (180) | 507 | The high tone of 0x91438 and 0x284374. |
| 0x90 (144) | 634 | The low tone of 0x91438 and 0x284374. |

The names "high" and "low" in `usb-host-probe` do not agree with the formula: 0xb4 gives the lower frequency. The formula is not measured on the real iPod. Measure one note with a tuner and record the result here.

An integer period gives an error of less than 1/(2 × value). For a value above 70 (below approximately 1300 Hz), the error is less than 13 cents.

## The callers

- 0x91438: seven alternating tones of 200000 µs (0xb4 and 0x90, the 0x90 tones two times longer), then a type-1 message.
- 0x284374: on event 0x89, two tones (0xb4, 0x90) of 200000 µs.
- 0x1dff28, 0x1dff34, 0x1dff40, 0x11e4cc, 0xa6aec, 0x1b91fc: other callers, not examined.

`tone` does not read the Clicker setting (key 0x60006088). The callers decide. In the emulator, the click of the Select button also calls `tone`.

## Use in a patch

- Send one note, and wait until it ends before the next note with a rest. A rest is a time with an empty buffer. A value of 0 writes 0x80800000, and the result of that write is not known.
- A patch that waits with the task sleep 0x11c9fc keeps the buffer short. Use `USEC_TIMER` for the time, so that the errors of the sleeps do not add. `something-comforting` does this.
- Notes without a rest between them can go in the buffer together, at most 15.

## Test results

- Emulator (2026-10-08, `something-comforting`): 37 calls of `tone` at the times of the note table (within approximately 10 ms). The emulator has no audio, and the event log showed no write to 0x7000a000.
- Real iPod: not tested.
