# A clock in the Split panel

Status (4 November 2026): versions 1.1, 1.2 and 1.4 operate in the emulator (Light, ⅔ – ⅓). Version 1.3 operates on a real iPod, with one fault that 1.4 corrects. Version 1.0 showed no clock. Refer to [The fault of version 1.0](#the-fault-of-version-10).

Status (6 November 2026): version 1.5 adds the analogue clock of the Clock app as an option. The research is static. Refer to [Version 1.5: the analogue clock](#version-15-the-analogue-clock).

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

## Version 1.4: "0 of 0" at the start

Owner report (real iPod, version 1.3, 4 November 2026): the clock shows, but at the start the panel also showed "0 of 0". After Play and Pause, it did not show.

Cause (static): the lookup hook hides the count line only for the panel object, and the patch learns that object at the first lookup of a clock line. In the Split View the count line is element 6 and the clock lines are elements 7–9. Thus the count line asked first and got "0 of 0". No notify reached it until a song change or a change of the pause clock.

Fix: when the patch learns the panel object (the first time, or a new object), it notifies the count line on that object one time. The notify posts a message (0x21f37c, 0x14a29c), so the count line asks again after this lookup, not inside it. The size is 1444 bytes. The owner reported that the emulator test is good.

## Version 1.5: the analogue clock

The owner asked on 6 November 2026 if the panel can use the analogue clock of Extras > Clock. The owner selected these items:

- A new option "Clock Face": Digital (the clock of version 1.4, the default) or Analogue (the face, then the day and the date).
- The face colour of the Clock app: white from 6:00 to 17:59, and black at other times.
- The size of the Apple pictures, 45 × 45, with no scale.

### The pictures

All clock pictures are 45 × 45. No larger clock picture is in the firmware. The 5 pictures of 142 × 142 (24395–24399) are the dial of Screen Lock.

| Pictures | Content |
|---|---|
| 24403, 24404 | The day face, and the day face with a blue ring (the selected row). |
| 24405, 24406 | The night face, and the night face with a blue ring. |
| 24407, 24408 | The grey and the blue outline of the row "New Clock". |
| 25007–25021 | The minute hand of the day face: 15 angles of one quadrant, in steps of 6°. |
| 25022–25036 | The minute hand of the night face. |
| 25037–25042 | The hour hand of the day face: 6 angles, in steps of 15°. |
| 25043–25048 | The hour hand of the night face. |
| 25049, 25050 | The centre dot of the day face and of the night face. |

The corners of each face are white. The hands of the day face have a white ground, and the hands of the night face have a black ground. The theme Dark Gray changes most of these pictures to flat faces, but it keeps the white corners and the grounds.

### The class of the clock

The firmware has one analogue clock: the View element class 0x5a80. Only View −568, the row of the Clock list, uses it. Element 0 of View −568 has the class 0x5a80, the tag `'DtTm'`, the ID 0x618a and the owner word 0x6180.

| Address | Fact | Evidence |
|---|---|---|
| 0x170874, 0x219b7c | Registers the class 0x5a80 with the constructor 0x1aaeec at each start. | Static |
| 0x1aaeec, 0x1ab4ac | Allocates 0x14c bytes, and calls the base constructor 0x21af84. Reads 5 IDs at class word + 0x50: the day face, the night face, the "New Clock" face, the first minute hand and the first hour hand. View −568 gives 24999, 25001, 25003, 25007 and 25037. | Static |
| 0x1ab4ac | Makes 50 picture bindings with 0x149e64 (binding, owner, ID). The faces are at + 0x80 to + 0x94 (each ID and ID + 1). The 30 minute hands are at + 0x98. The 12 hour hands and the 2 dots are at + 0x110 (the dots at + 0x140 and + 0x144). | Static |
| 0x1ab4ac | + 0x148 = slot + 0x14 of the owner, with the class ID 0x6180. | Static |
| 0x21af84 | The base element: + 0x14 the owner, + 0x18 the tag, + 0x1c the ID (16 bits), + 0x20 the flags, + 0x28 the 4 edges. | Static |
| 0x21a4f4 | Makes an element of a View. The word at class word + 0xc selects the owner. The panel labels use 0x2b00. | Static |
| 0x2370f0 | Slot + 0x5c of the Clock provider. For `'BMap'` and the IDs 24999–25004 it gives the pictures 24403–24408. | Static |
| 0x250760 | Resolves a binding at its first draw: `lookup(owner, 'BMap', ID)`. | Static |
| vtable 0x66d770 | + 4 is 0x1ab664: the base destructor 0x21b064, then `free`. It does not free the 50 bindings. + 0x70 is 0x1ab460, the draw. | Static |
| 0x1ab460 | Makes the graphics context (0x211bd4, 0x21aad0) and the rectangle (0x2559d8). Then `bl 0x1ab064` at 0x1ab498 (0xebfffef1). This is the only call of 0x1ab064. | Static (FindXrefs) |
| 0x1ab064 | The draw of a row. It reads the list (`*(*(self + 0x10) + 0x10)`) and the time of the row (0x236f58 with + 0x148). An hour from 6 to 17 gives the day face (+ 0x80), else the night face (+ 0x88). Selected rows use + 0x84 and + 0x8c. | Static |
| 0x1ab064 | Keeps the colour (0x2551dc) and the mode (0x2551d4). Sets the colour white (0x2106dc) and the mode 0x20, and draws the face (0x250714, 0x2506bc). Calls 0x1ab1e4, 0x1aafa4 and 0x1aaf38. Sets the colour and the mode again. | Static |
| 0x1ab1e4 | The minute hand (element, gc, rectangle, face, time). The angle is minutes × 6. The picture is (angle in the quadrant) / 6, + 15 for the night face. | Static |
| 0x1aafa4 | The hour hand. The angle is (hours modulo 12) × 30, + 15 for minutes 15–44, + 30 for minutes 45–59. The picture is (angle in the quadrant) / 15, + 6 for the night face. | Static |
| 0x1ab270 | Copies the hand into a surface of 45 × 45 (0x13b91c, 0x211ac8) and turns it for the other quadrants (0x21190c, 0x2118b4). Blits it with 0x210114. The key colour is white for a day face and black for a night face. | Static |
| 0x1aaf38 | The centre dot: + 0x140 for a day face, + 0x144 for a night face. | Static |

The time of 0x236f58 and the calendar structure of 0xd252c have the same layout: + 1 the minutes, + 2 the hours. Thus the patch can give the current time to 0x1ab1e4 and 0x1aafa4.

The mode 0x20 with the colour white makes the white corners of the face transparent. 0x1ab270 sets the key colour of each hand.

### Slot + 0x14: the type test

Slot + 0x14 of an object gives the object if the class ID agrees. Else it asks the base class, and the last base gives 0.

| Object | Slot + 0x14 | Class IDs that agree |
|---|---|---|
| The Clock provider (vtable 0x677148) | 0x236f04 | 0x6180, 0x2480, 0x180, 6, 5, then the base 0x13cdf4 |
| The panel data object (vtable 0x673428) | 0x206ec8 | 0x2b00, then the base 0x21f23c (5, 4, 3, 1) |
| The clock element (vtable 0x66d770) | 0x1aaf20 | 0x5a80, 0x1080, 0x1000, then the base 0x13cdf4 |

Thus a clock element with the owner word 0x2b00 gets the panel data object as its owner. Then + 0x148 is 0. In the Clock app, + 0x148 is the Clock provider, never 0. The patch uses this value to tell the panel clock from a row of the Clock app.

The base element code has one lookup with the ID of the element: the tag `'ClrR'` at 0x2194b4 (in the body of 0x21acac). It runs only for elements with all the flag bits 0x38000. The clock element has the flags 0xa00. The methods of the class 0x5a80 (vtable 0x66d770: + 4, + 0x14, + 0x70 and the base methods) do not ask for data with the ID of the element. Other classes ask for `'DtTm'` with their own code, for example at 0x1bc760.

### The design

The build adds a copy of the clock element to the Split View. The element has the ID 0x7e44, the owner word 0x2b00 and the direct picture IDs 24403, 24405 and 24407. The hand IDs are 0: refer to [The scale](#the-scale-static-6-november-2026). Only the Clock provider answers the IDs 24999–25004, so the copy uses the picture IDs. The picture lookups go to the language manager and the root object, as for the other pictures.

A scan found no use of 0x7e44 in the code, the Views, the Menus or `TCmd` 9088.

| Hook | Kind and place | Expect | Action |
|---|---|---|---|
| Draw | `bl` at 0x1ab498 | 0xebfffef1 | If + 0x148 is not 0, call 0x1ab064 (the Clock app). Else keep the element. If the clock shows, draw the clock at 90 × 90 with the current time. Refer to [The scale](#the-scale-static-6-november-2026). |
| Delete | `word` 0x66d774 | 0x001ab664 | For the panel element: forget the element, and free its bindings as the label destructor 0x244aac does (0x149e8c, then `free` 0x25a8f4). Then call 0x1ab664. |

The clock shows with the same test as the text lines: no song title, or the pause clock. At each notify of the clock lines, the patch also calls `view_invalidate` (0x21ac04) on the element. Thus the hands change at each timer event, and the face goes away when a song starts.

With Analogue, the build adds the face and the lines of the day and the date. It does not add the line of the time.

### The first emulator test (45 × 45)

Owner, 6 November 2026: Light, ⅔ – ⅓, Clock After a Pause = 30 Seconds, test library. The analogue face showed in the panel. The owner reported that the face is probably too small. The other steps (the minute change, a song, a pause, the Clock app) are not reported.

### The scale (static, 6 November 2026)

The owner asked if the firmware can draw the clock larger. It cannot:

| Address | Fact |
|---|---|
| 0x1216a0 | The blit core. It clips the source and the target rectangles and copies the pixels 1:1. It has no step and no division. Its only callers are 0x210114, 0xbff74 and 0xdcb9c. |
| 0x2506bc, 0x2507b4, 0x210114 | Each picture draw goes to 0x1216a0. |
| 0x21190c | Swaps the pixels of a square surface of 16 bits across the diagonal, in place. With 0x2118b4 (a mirror through 0x121eb4), this turns a hand. |
| 0x13b91c, 0x13b6c8 | Makes a work surface (0xb4 bytes) for a rectangle and a format. A rectangle is (top, left, bottom, right): 0x255894 gives the height ([2] − [0]) and 0x255884 the width ([3] − [1]). The pixels come from the heap (0x11ca20, tag 0x1a). The surface stores the pixels in rows: + 4 the pixels, + 8 the bytes of one row (from the width), + 0xc the bits of one pixel, + 0x14 the format (bit 0x2000 swaps the bytes), + 0x18 the clip. |
| 0x211ac8, 0x211c04 | Makes and frees a graphics context (0x44 bytes) on a surface. + 0x1c is the surface. |
| 0x13ba74 | Frees a work surface and its pixels. |
| RAM 0x10883614 + 0x1a | The format that 0x1ab270 uses for its work surfaces. |

A search of the full decompile for functions with 2 loops, a division and 16-bit pixel copies found only sound sample code. No string has "scale" or "zoom".

The owner compared 3 methods in a mock-up from the real pictures and selected bilinear with a round mask. The emulator test of that build (owner, 6 November 2026) showed a face of 90 × 90 at the correct place, but the owner reported that it was very blurry. A scale of a 45 × 45 picture cannot add detail. The owner then compared 4 methods in a second mock-up and selected the Apple face with sharp hands. The emulator test of that build (owner, 6 November 2026): the hands were sharp, but the face was not. Thus version 1.5 draws all parts at 90 × 90, and takes the colours from the Apple face:

1. Draws the Apple face at 45 × 45 on white in a work surface, as 0x1ab064 draws it. The theme and the day or night face give the colours.
2. Draws the ground at 90 × 90 in a second work surface. Out of a circle of radius 44, the key colour white. From radius 42 to 44, the rim colour: pixel (37, 7) of the Apple face (radius 21 at 45°, between 2 ticks). In the circle of radius 42, the colour of column 17 of the Apple face at the same height (row 2 to 42). Column 17 has no tick, and it gives the shine and the gradient.
3. Draws 12 ticks from radius 44 to radius 35, 2.5 pixels wide, in the colour of pixel (22, 2) of the Apple face (the tick at 12).
4. Draws the hour hand (22 pixels, 1° steps), the minute hand (36 pixels, 6° steps) and a dot (radius 5). The colour is the colour of the Apple dot: (49, 48, 49) for the day face, (239, 239, 239) for the night face.
5. Changes a white pixel in the face to 0xffdf, and blits the result into the panel with the key colour white (mode 0x20).

Each shape uses 4 × 4 samples in each pixel, so the edges are smooth. A table of 91 bytes gives sin(0°–90°) × 255. The code has no division. The layout gives 0 as the IDs of the first minute hand and the first hour hand. Then 0x1ab4ac makes only the 6 face bindings. It does not write the 44 hand words, so the delete hook frees the hand bindings only if the IDs are not 0.

The first build of this method drew the hands reflected across the diagonal, and the shine as vertical bands. The cause was a wrong order of x and y. A rectangle of the firmware is (top, left, bottom, right), and a work surface stores the pixels in rows. A headless emulator run (6 November 2026, 22:06, night face, Light, ⅔ – ⅓, test copy with counters) then showed the correct hands, a horizontal shine and sharp ticks. The counters gave 17 panel draws, 17 faces drawn, 15 invalidates, 1 panel element, no draw for the Clock app and no delete.

The face element is 90 × 90: top 34, left 222 (⅔ – ⅓) or 194 (½ – ½). The day line is at 128 and the date line at 150. The work objects are static, because only the UI task draws. The 2 surfaces use approximately 20 KB of the heap during one draw.

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
