# A clock in the Split panel

Status (4 November 2026): versions 1.1 and 1.2 operate in the emulator (Light, ⅔ – ⅓). Version 1.0 showed no clock. Refer to [The fault of version 1.0](#the-fault-of-version-10). Not tested on a real iPod.

The owner wants the right panel of the Split main menu to show the time, the day and the date when there is no current song. The owner reports that the iPod classic 6G/7G does this. All addresses are osos offsets of firmware 1.3. The method is static research with Ghidra, project `osos13`, read-only, and a full decompile.

## The behaviour of the classic

A web search found reports of a full-screen clock on the iPod classic 6G. The clock shows the time and the battery after an idle time on battery power. The search found no report of a clock in the right panel of the main menu. The owner selected the panel clock on 4 November 2026:

- The panel shows 3 lines: the time, the day of the week and the date.
- The clock shows only when the panel has no current song. A paused song keeps the cover and the song text.

## The summary

- The firmware has a function that gives the current time in the calendar structure. Refer to [date-time.md](date-time.md).
- The language manager has a method that formats the calendar structure with the formats of the current language. The time obeys the 12-hour or 24-hour setting.
- A label in the panel gets its text by its element ID through the general lookup 0x21f254. A label with no answer does not draw.
- The firmware tells the provider when the song changes. A patch can send the same message for the clock lines.
- The status object has 6 timers. A patch can add its own timer to this object, for an event at each minute.

Thus a patch with 3 hooks and 3 new text elements in the Split View can show the clock. No change to a shared View or a shared Type is necessary.

## The parts

| Address | Function | Evidence |
|---|---|---|
| 0xd252c | Gives the current time in the calendar structure: + 0 seconds, + 1 minutes, + 2 hours, + 3 day, + 4 month, + 6 year (16 bits), + 8 day of the week. | Static ([date-time.md](date-time.md), 14 callers) |
| 0xc8fd0 | Writes + 8 as the day number modulo 7. Day 1 is 1 January of year 1, a Monday. Thus 0 is Sunday, as `tm_wday`. | Static |
| 0xcce88 | Gives the language manager: the word at + 0x14 of the object from 0x14b460. | Static. 0x2506b4 reads the same word + 0x14 |
| 0x105dc8 | Copies the date strings of `LDTm` 128 into the locale at manager + 0x44: 12 month names (+ 0), 12 short month names (+ 0x180), 7 day names (+ 0x1f8), 7 short day names (+ 0x2d8), AM and PM, and 14 formats from + 0x32f. | Static |
| 0x1529d4 | Selects a language and reads the formats again. If the 24-hour flag (+ 0x4c4, property 0xa9) is set, it writes `%H:%M` to manager + 0x473. | Static. 0x1528f4 sets the flag and reads the formats again |
| 0x250c50 | Slot + 0x7c of the manager (vtable 0x668f1c): `(manager, buffer, size, style, calendar)`. The styles 0 to 3 give a month or a day name. The styles 4 to 0x12 give one of the formats. | Static (DumpCode) |
| 0xe6880 | The `strftime` of the firmware: buffer, size, format, a `tm` of 36 bytes, locale. Slot + 0x88 (0x250e74) calls it through 0x1137f4. | Static |
| 0x1680dc, 0x19e11c | Call slot + 0x7c with style 0x11 (the short time). | Static |
| 0x21f254, 0x21f418 | The general lookup. Calls slot + 0x5c of each object `(object, 'Str ', ID, &out)`, and then the parent at + 0x10. | Static |
| 0x1e804c | Slot + 0x5c of the main provider (vtable 0x670f54, word 0x670fb0). For a text ID it writes the address of a C string to `*out` and gives 1. For an unknown ID it gives 0. | Static. `battery-display` uses case 0x63fc |
| 0x1e9818 | The song change. Calls the notify method of the provider with `'Str '` (0x53747220) and 0x63bd, 0x63be, 0x63bf and 0x63c3. | Static |
| 0x21f37c | The notify method (word 0x670fa8, slot + 0x54): `(object, type, ID)`. Posts a change message. | Static. 0x1d91dc uses it for the status items |
| 0x1d9430 | Makes the status object (vtable 0x6701bc, 0x134 bytes). Makes 6 timers with 0x13d7c8. The timer at + 0xa0 has 30 000 ms (the battery), the timer at + 0xc8 has 300 000 ms. Object + 0x18 is the main provider. | Static. The 30 s agrees with the emulator in [battery.md](battery.md) |
| 0x13d7c8 | `(owner, timer, 0, 0)`: makes a timer of 0x28 bytes. + 0x20 is the owner. | Static. 0x12e78c and 0x1d9430 use it |
| 0x151c24, 0x151694 | Set the period of a timer in ms, and start the timer one time. | Static. `album-art` uses 0x151694 |
| 0x1d93c4 | Slot + 0x30 of the status object (word 0x6701ec): the event method. For an event of type 9 it calls 0x1d8e68, which compares `ev[2]` with the 6 timers. An unknown timer gives 0. | Static. The browse list has its event method at the same slot (0x6772c0 − 0x677290) |
| 0x69ce1c | A class table holds the factory 0x1d8dd8 of the status object. | Static |

The status object stays for the whole run: `battery-log` wrote a sample each 30 s for 20 hours on the real iPod from its timer. Refer to [battery.md](battery.md).

## The formats

The styles that the patch uses, measured in `LDTm` 128 and the English main block:

| Style | Manager offset | String | English format |
|---|---|---|---|
| 0x11 | + 0x473 | 0xb5 | `%-I:%M %p`, or `%H:%M` with the 24-hour setting |
| 2 | + 0x23c + 32 × day | — | The full name of the day |
| 8 | + 0x3b3 | 0xab | `%-d %B %Y` (the option Long Month) |
| 14 | + 0x453 | 0xb3 | `%b %-d %Y` (the option Short Month, the default) |

Each language block has its own `LDTm` 128. Thus the names and the formats follow the language of the iPod. All 24 language blocks have string 0xb3 with the year, for example German `%-d. %b %Y`, French `%-d %b %Y` and Japanese `%Y/%b/%-d`.

The owner reported on 4 November 2026 that "4 November 2026" was cut off in ⅔ – ⅓. Thus Short Month is the default.

## The patch

Version 1.1:

| Hook | Kind and place | Expect | Action |
|---|---|---|---|
| Lookup | `b` at 0x21f254 | 0xe92d40f8 | For the 3 clock IDs: if the song title (0x63bd, from the same first object) is empty, give the text. Else give 0. Keep the first object of the lookup. |
| Notify | word 0x670fa8 | 0x0021f37c | After a notify of 0x63bd, notify the 3 clock IDs on the kept object. |
| Event | word 0x6701ec | 0x001d93c4 | At the first event, make and start the patch timer. At the patch timer event, notify the 3 clock IDs on the kept object, and start the timer for the next minute. |

The language manager is `str_table()` 0x21f3b8. A clock chip with day 0 or month 0 gives no text, so the clock does not show.

The clock IDs are 0x7e41 (time), 0x7e42 (day) and 0x7e43 (date). A scan found no use in the code, the Views, the Menus or `TCmd` 9088. No other patch hooks the 3 words.

The text test uses the song title, so the clock and the song never show at the same time.

## The fault of version 1.0

Version 1.0 hooked the text method of the main provider (word 0x670fb0) and used 0xcce88 for the language manager. In the emulator, the panel showed only "0 of 0".

A test copy with counters gave these values (emulator, owner at the main menu, 4 November 2026):

| Counter | Value |
|---|---|
| Calls of the text hook | 729 |
| Calls for 0x7e41–0x7e43 | 0 |
| Event hook calls, patch timer events | 183, 56 |

A second test copy hooked 0x21f254 and recorded the chain of each lookup (the first word of the vtable of each object):

| Item | Result |
|---|---|
| Chain for a clock ID and for the artist line 0x63be | The data object (first method 0x207304), the language manager (first word 0), the root object (0x1aeb30). The main provider is not in the chain. |
| The answer of the chain for a clock ID | 0 (no object answers). |
| Clock requests, texts made, song shown | 33, 33, 0 |
| Notifies to the data object, timer events | 27, 23 |

Thus the data object of the panel gives only the music IDs to the main provider. A hook on the vtable of the main provider cannot see the clock IDs. The fix answers the IDs at 0x21f254, as other patches do for their texts. The notify also goes to the data object, because the labels listen to it.

The emulator also gave all zeros from the clock chip. The firmware made "27 June 64432" from day 0 of month 0 of year 0. The emulator patch 0003 corrects this. Refer to [emulator.md](emulator.md#the-running-clock).

## The emulator test of version 1.1

Owner, 4 November 2026: Light, ⅔ – ⅓, folder library, Short Month, emulator patch 0003. The panel showed the time of the Mac, "Wednesday" and "Nov 4 2026", and the owner reported that it looks great.

## Version 1.2: no "0 of 0", and the clock after a pause

The owner asked on 4 November 2026 for 2 changes: no "0 of 0" with no song, and the clock again after a pause. The option "Clock After a Pause" gives Never, 1 Minute, 5 Minutes (the default) or 15 Minutes. Only Play brings the paused song back.

A test copy recorded these values in the emulator (owner: play, pause, Now Playing):

| Item | Result |
|---|---|
| 0x9ba00(provider + 0x1c) | 0 with no song, 1 during playback, 2 after Pause. |
| Requests of the panel object | `'Str '` 0x63bd–0x63bf, 0x63c3, 0x7e41–0x7e43, `'Draw'` 0x63c7 (the cover), `'BMap'` 0x63ce, `'Cntl'` 0x63c2 and other IDs. |
| Song title requests from another object | 30, all from the main provider itself. Thus Now Playing asks the main provider directly, not the panel object. |

The design:

- The lookup hook gives no answer to the panel object for 0x63c3 when the song title is empty.
- At each minute event, the patch reads the play state. More than `pause_minutes` events in the state 2 set the pause clock. Then the panel object gets no answer for the song lines, the count and the cover, and the clock lines show.
- At each notify on the main provider while the pause clock shows, the state 1 clears it. Thus Play brings the song back at once.
- Each change notifies the song lines, the count, `'Draw'` 0x63c7 and the clock lines on the panel object.

The size is 1392 bytes with `__attribute__((minsize))` (1854 bytes without it).

Version 1.3 (4 November 2026): the owner asked for 30 Seconds. The timer now comes at each :00 and :30, and the pause counts seconds in steps of 30. Thus the clock shows `pause_seconds` to `pause_seconds` + 30 seconds after the pause. The option values are seconds: 0, 30, 60, 300 (the default) and 900, with the new `id` `pause_time`. The code has no division, so it needs no `__aeabi_uidiv`. The size is 1396 bytes.

The emulator was slow for approximately 30 s after each Pause and Next. The cause was in the emulator, not in the patch. Refer to [emulator.md](emulator.md#the-cop-sleep-fix). With the emulator patches 0001–0004, the owner reported that version 1.2 works.

## The fonts

| Type | Font | Alignment | Colour in Dark Gray |
|---|---|---|---|
| 24236 | Podium Sans 28 | Centre | Black (no change) |
| 24230 | Podium Sans 22 | Centre | Black (no change) |
| 24235 | Podium Sans 28 | Left | White |
| 22551 | Podium Sans 22 | Left | White |

Thus a large centred time in Dark needs a style from the patch, as `battery-display` does with `apply_type` (0x21a168). The emulator test decides this.

## "Time in Title"

The key of Settings > Date & Time > Time in Title is 0x600060a8 (Menu 24604). The settings object keeps it at + 0x39 (0x192994, 0x1919d8, 0x193b90). No other ARM code and no `TCmd` data has the key. The patch does not need this setting.

## Open points

- The change from a stopped song (the end of the play list) to the clock is not tested. The pause and Play are tested in the emulator.
- Dark, ½ – ½, Switch on iPod, Long Month and the Swift build path are not tested.
- After a sleep, the old minute can show until the timer event comes.
- The patch keeps the data object of the last clock request. If the firmware makes the main menu again, the next request gives the new object.
