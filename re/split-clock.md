# A clock in the Split panel

Status (4 November 2026): static research is complete. The patch `split-clock` is on the branch `split-clock`. It is not tested in the emulator or on a real iPod.

The owner wants the right panel of the Split main menu to show the time, the day and the date when there is no current song. The owner reports that the iPod classic 6G/7G does this. All addresses are osos offsets of firmware 1.3. The method is static research with Ghidra, project `osos13`, read-only, and a full decompile.

## The behaviour of the classic

A web search found reports of a full-screen clock on the iPod classic 6G. The clock shows the time and the battery after an idle time on battery power. The search found no report of a clock in the right panel of the main menu. The owner selected the panel clock on 4 November 2026:

- The panel shows 3 lines: the time, the day of the week and the date.
- The clock shows only when the panel has no current song. A paused song keeps the cover and the song text.

## The summary

- The firmware has a function that gives the current time in the calendar structure. Refer to [date-time.md](date-time.md).
- The language manager has a method that formats the calendar structure with the formats of the current language. The time obeys the 12-hour or 24-hour setting.
- A label in the panel gets its text from the main provider by its element ID. A label with no answer does not draw.
- The firmware tells the provider when the song changes. A patch can send the same message for the clock lines.
- The status object has 6 timers. A patch can add its own timer to this object, for an event at each minute.

Thus a patch with 3 `word` hooks and 3 new text elements in the Split View can show the clock. No change to a shared View or a shared Type is necessary.

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
| 8 | + 0x3b3 | 0xab | `%-d %B %Y` |

Each language block has its own `LDTm` 128. Thus the names and the formats follow the language of the iPod.

## The patch

| Hook | Word | Expect | Action |
|---|---|---|---|
| Text | 0x670fb0 | 0x001e804c | For the 3 clock IDs: if the song title (0x63bd) is empty, give the text. Else give 0. |
| Notify | 0x670fa8 | 0x0021f37c | After a notify of 0x63bd, notify the 3 clock IDs. |
| Event | 0x6701ec | 0x001d93c4 | At the first event, make and start the patch timer. At the patch timer event, notify the changed clock lines and start the timer for the next minute. |

The clock IDs are 0x7e41 (time), 0x7e42 (day) and 0x7e43 (date). A scan found no use in the code, the Views, the Menus or `TCmd` 9088. No other patch hooks the 3 words.

The text test uses the song title, so the clock and the song never show at the same time.

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

- The emulator plays no music. Thus only a real iPod can test the change from a song to the clock.
- After a sleep, the old minute can show until the timer event comes.
