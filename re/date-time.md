# The date and the time in the firmware

This note gives the format of the date in firmware 1.3 of the iPod Video. It also gives the limits of the date, for example the 2038 bug. All addresses are osos offsets. The method is static research with Ghidra, project `osos13`.

## The summary

- The firmware has no 64-bit date.
- The firmware keeps the date in 4 formats. These are the clock chip format, a calendar structure, 32-bit seconds and the FAT date.
- The seconds are unsigned. Thus 19 January 2038 does not change the conversions in this note.
- The first limit is 6 February 2040. On this date, the 32-bit seconds from 1904 wrap to 0.
- The clock chip keeps 2 year digits. Thus the clock cannot show a year after 2099.

## The formats

| Format | Functions | Size | Epoch or base | Last value |
|---|---|---|---|---|
| Clock chip | Read 0xb0038, write 0xbc63c | 7 bytes of BCD | Year = 2000 + 2 digits | 2099 |
| Calendar structure | 0xc8f3c, 0xc8fd0 | Unsigned 16-bit year | Year 1 | 65535 |
| Unix seconds | 0xd5b0c, 0xd8530 | Unsigned 32 bits | 1970-01-01 | 2106-02-07 06:28:15 UTC |
| Mac seconds | 0xa4fc0, 0x94f18 | Unsigned 32 bits | 1904-01-01 | 2040-02-06 06:28:15 UTC |
| FAT date | Read 0xe47d8, write 0xe59cc | 7-bit year | 1980 | 2107 |

## The clock chip

The function 0xb0124 gets the time. It calls 0xb0038 if 0x120878 gives a value that is not 0. Otherwise it reads a hardware timer register. The research did not trace this second path.

The function 0xb0038 calls 0x2837e0. That function reads 7 bytes from register 0x0a through 0x283540. The argument 1 selects register 0x11. The function 0xb0038 changes each BCD byte to binary with 0x11df88. Then it adds 2000 to the year.

The function 0xbc63c subtracts 2000 from the year. It changes each byte to BCD with 0x11b940 and calls 0x2837f8.

The function 0xa09c4 tests bit 0 of the flags of the time. If the bit is 0, the function uses 1 January 2002. The word at 0xa0aa4 has the year, 0x7d2.

The function 0xd252c gives the current time of day in the calendar structure. It uses the functions above.

## The calendar structure

| Offset | Size | Value |
|---|---|---|
| +0 | 1 byte | Seconds |
| +1 | 1 byte | Minutes |
| +2 | 1 byte | Hours |
| +3 | 1 byte | Day |
| +4 | 1 byte | Month |
| +6 | 2 bytes | Year |
| +8 | 1 byte | Day of the week |

The function 0xc8f3c changes a date to a day number. Day 1 is 1 January of year 1. The function 0xc8fd0 changes a day number to a date. The function 0xd59cc compares two structures one field at a time, so it does not use seconds.

## The seconds

The function 0xd5b0c changes a structure to Unix seconds:

1. It compares the date with the table at 0x2a9c20, which holds 1970-01-01 00:00:00.
2. It gives 0 if the date is earlier. There is no upper limit.
3. It adds the word at 0xd5b6c (-719163) to the day number.
4. It multiplies the result by the word at 0xd5b70 (86400).
5. It adds the hours, the minutes and the seconds.

The value 719163 is the day number of 1 January 1970.

The function 0xd8530 changes Unix seconds to a structure. It divides with 0x82694. This function is an unsigned divide, so a value with bit 31 set gives a correct date. The function 0x21e4c8 uses an unsigned compare of the seconds. The functions 0xff994 and 0x10efdc use the unsigned difference of two values.

The functions 0xa4fc0 and 0x94f18 give Mac seconds in the same way. They subtract 695056, the day number of 1 January 1904. The word 0xa9b10 at 0x4fc1d8 and an immediate value in 0xa4fc0 hold this number.

The function 0xe4d28 changes Mac seconds to Unix seconds. It adds the word at 0xe4d74 (0x83da4f80, which is -2082844800). The function 0xe5a78 does the opposite. It adds the word at 0xe5ac4 (0x7c25b080).

## The paths that set the date

All paths go to 0xa0cec, then 0xb3764, then 0xbc63c.

| Path | Year test |
|---|---|
| 0x1f4c9c, from 0x1f3c18 | Yes. `param_2 - 2000U < 100`, so the year must be 2000 to 2099. |
| 0xda584, a jump from 0x19308c | None in this function. |
| 0x12a090, from 0x12b964 | None. It reads 12 bytes from a stream and calls 0xb3764 directly. |

## The audit of all uses

The audit used `FindXrefs.java` on 17 date functions. The result was 138 references in 91 functions. The research read the code at each reference.

| Use | Functions | Result |
|---|---|---|
| Signed compare of seconds | None found | The 2038 bug has no effect at these references. |
| Compare of two dates | 0xff994, 0x10efdc, 0x90e84, 0x252294 | Safe. They compare calendar structures, or use an unsigned difference. |
| Next alarm | 0x21e4c8 | Safe to 2106. The compare is unsigned. |
| Time zones | 0x236f58, 0x23846c, 0x2382e8 | Safe to 2106. They add and subtract 32-bit seconds. |
| Calendar views, day numbers | 0x168088 to 0x168650, 0x14a834 to 0x14b10c, 0x17eb70, 0x1f12b8 to 0x1f13b4, 0x22c178 | Safe. A day number uses no seconds. |
| Text of a date | 0xc2184, 0x10ab54, 0x1680dc, 0x1c2100, 0x2127fc | Safe to 2106. 0xc2184 subtracts 1900 from the year. |
| Timers, not dates | 0xa7a30, 0x181b90, 0x19d5d4, 0x246ef8, 0x19e1b8 | Not relevant. These values are elapsed time. |
| Last played, track + 0x94 | Write 0x21cb98, read 0x21bfcc | Stays correct after 2040. There is no range test, and the conversion wraps. |
| Track + 0xa4, probably last skipped | Write 0x21cc74, read 0x21c364 | Stays correct after 2040, for the same reason. |
| Track + 0x54, + 0x68 and record + 0x28 | Read 0x21dd60, 0x21e138, 0x21bbbc | Stays correct after 2040. There is no range test. |
| Dates of new files | 0xa9348, 0xa96c0, 0xb6770, 0xd6de8, 0x10bfd0 | The value wraps in 2040. The research did not trace the readers. |

## The effect of each date

| Date | Value | Effect |
|---|---|---|
| 2038-01-19 03:14:08 UTC | Bit 31 of Unix seconds is set | None found. |
| 2040-02-06 06:28:16 UTC | Mac seconds wrap to 0 | 3 small effects. Refer to the list below. |
| 2099-12-31 | The last year of the clock chip | The next year has the value 2000. |
| 2106-02-07 06:28:16 UTC | Unix seconds wrap to 0 | The clock chip stops before this date. |

The clock does not use seconds. Thus the wrap of 2040 does not stop the clock. The conversion 0xe4d28 stays correct, because the addition also wraps at 32 bits.

These are the 3 effects of the wrap of 2040:

1. The functions 0x9cd9c and 0x21c42c accept a date at + 0x18 only if the unsigned value is not less than 0x7c25b080. After the wrap, a new date fails until 2106. The firmware then does not show the date. The research did not identify the field.
2. The function 0x1beb08 applies the same test to the date of a photo item at + 0x28. The function 0xf4acc sorts these items with an unsigned compare, so a new item goes to the start of the list.
3. The function 0xa16dc compares the current time with a stored file value at + 0x100. It stops early if the current time is less. A value from before the wrap blocks the operation. The research did not identify the operation.

## One other result

The functions 0x1996a4 and 0x19aae4 write Unix seconds from 0xd5b0c to the photo item at + 0x28. The functions 0x1be5c0 and 0x1beb08 read this field as Mac seconds. A Unix value from 2026 is less than 0x7c25b080, so 0x1beb08 gives false. The research did not make sure that the input of the write is a normal date. This result has no relation to the 2038 bug.

## The limits of this research

- No test ran on the emulator or on a real iPod with a date after 2038.
- The audit covers each call of the 17 functions. It does not cover code that copies a stored date and compares it in a different function.
- The research did not find the year limits of the Date & Time menu. The path 0xda584 has no year test.
- The research did not examine how a computer reads the dates that the iPod writes.
- Register 0x0a is the first clock register of the PCF50605 in the public data sheet, as far as this project remembers it. The firmware does not give the name of the chip at this function. The task name `PCFPowerMgr` agrees with this result.
- The year limit 2099 comes from the 2 BCD digits. The leap year rule of the chip was not examined.
