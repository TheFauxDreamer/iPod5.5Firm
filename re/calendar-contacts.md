# Contacts and Calendars on the iPod (RetailOS 1.3, iPod Video)

This note gives the research of the stock readers of contacts and calendars. It also gives the design of a translation layer in the iPodFirm app. The layer reads the contacts and the calendars of macOS and writes files that the iPod reads correctly.

The research used Ghidra (project `osos13`, base 0) on 5 November 2026. All addresses are osos offsets. The emulator tests are in the section [Emulator test](#emulator-test). Their results are not recorded yet.

## The result in short

- The iPod reads all files in `/Contacts` and `/Calendars`. It does not examine the file extension. It skips only `.DS_Store`.
- One parser reads both formats. It reads `NAME;PARAMS:VALUE` lines. The names and the parameters are not case-sensitive.
- The parser reads Unicode only if the file starts with a BOM. A UTF-8 file without a BOM is read as Latin-1 or Mac Roman. macOS writes UTF-8 without a BOM.
- The parser does not decode the escapes `\n`, `\,` and `\;`. The backslash stays in the text.
- A photo must have `ENCODING=BASE64` or no encoding parameter, and `TYPE=JPEG`. macOS writes `ENCODING=b`. The iPod does not show that photo.
- A contact must have `N`, `FN`, `NICKNAME`, `ORG` or `EMAIL`. The iPod keeps a maximum of 4000 contacts.
- A date must use the basic form `YYYYMMDD` or `YYYYMMDDTHHMMSS[Z]`.
- The iPod ignores `RECURRENCE-ID`. It ignores `EXDATE` with `VALUE=DATE`. A moved or deleted occurrence of a repeated event is thus wrong on the iPod.

Conclusion: the macOS export does not work correctly as it is. A translation layer in the app must write a small dialect. Section [The iPod dialect](#the-ipod-dialect) gives the rules.

## Where the files are

| Item | Value | Evidence |
|---|---|---|
| Folder of the contacts | `Contacts/` at the root of the iPod volume. The string is at 0x678ceb. | Static |
| Folder of the calendars | `Calendars/` at the root. The string is at 0x678ce0. | Static |
| Folder table | The data at 0x69c450 holds a flag (1), then `Contacts`, `Contacts/`, `Calendars`, `Calendars/`, `Notes`, `Notes/`, `Recordings/`, `iPod_Control/iTunes/`. The code reads the same layout at RAM 0x1081e1ac. | Static |
| Walk of the contacts | 0xc9f88 walks the folder at RAM 0x1081e1ac + 8 and calls 0xd1fc4 for each file. | Static |
| Walk of the calendars | 0xe5afc walks the folder at RAM 0x1081e1ac + 0x10 and calls 0xfc99c for each file. | Static |
| Filter | 0xdd480 skips a path that contains `.DS_Store`. There is no extension filter. | Static |
| Entries | The walk skips an entry if bit 0 of its attribute byte is set, or if a second flag is set. The walk is made with the value 1 for "recursive" (0x1e45d4). Case C14 tests the subfolders. | Static |
| Sample files | At the start, 0x1b9ca8 can write `ipod_created_instructions.vcf` and `ipod_created_sample.vcf` from the templates at 0x678c4f and 0x6789aa. The condition is 0x1ec028. The research did not examine it. | Static |

### When the iPod reads the files

The task `LoadDataTasks` (made at 0x1ba2e0) runs 0x1b9b3c. The loop waits for a message. Then it reads the notes, the contacts (0x1b9484) and the calendars (0x14a9b0) again. 0x1ba368 sends the message at the start. 0x1eaf5c also calls 0x1ba368. This is probably the end of the disk mode, but the research did not confirm it.

The load runs in the background. The Contacts screen shows "Contacts loading." until the load is complete.

## The parser

### The text encoding of a file

0xe4be8 reads the first bytes of the file:

| First bytes | Code | Encoding |
|---|---|---|
| `FE FF`, or a first byte 0 | 4 | UTF-16 big-endian |
| `FF FE` | 5 | UTF-16 little-endian |
| `EF BB BF` | 3 | UTF-8 |
| Other | 10 | Refer to the next paragraph |

For code 10, 0x10f0c0 calls 0x1705dc. The result depends on the language of the iPod. Japanese gives 6, Korean 9, Simplified Chinese 8 and Traditional Chinese 7. All other languages give 1. 0x10f0c0 changes 1 to 2 if the flag at RAM 0x1081e1ac is 1 and two values of the directory entry are 0.

0x1de17c makes the decoder for a code. Code 2 is Mac Roman (0x1ac2e4). Code 3 is UTF-8 (0x157914). Code 6 is Mac Japanese (0x1ddbf4). Codes 7 to 9 are the Chinese and Korean decoders (0x167e08). Code 1 has no decoder: each byte becomes one character (Latin-1). Case C02 shows if code 1 or code 2 applies.

> **Result:** a file without a BOM is not UTF-8 for the iPod. Write `EF BB BF` at the start of each file.

The parameter `CHARSET=` of one line changes the encoding only for these values (0x141434): `MACINTOSH` gives code 2, `X-MAC-JAPANESE` gives code 6. Other values, for example `UTF-8`, have no effect.

### Lines

| Rule | Value | Evidence |
|---|---|---|
| Line end | LF, CRLF or CR (0x170794, 0x1707f8). | Static |
| Folding | A line end and then a space or a tab continues the line. The space or the tab is removed (0x1c039c, 0x1c0404). | Static |
| Name and parameters | 0x1afa9c reads up to the first `:` that is not in quotes and not after a backslash. The maximum is 0x400 (1024) characters. A longer line stops the file. | Static |
| Group prefix | 0x170354 removes the part before the first `.` of the name. `item1.EMAIL` becomes `EMAIL`. | Static |
| Value length | 0x16fff0 keeps a maximum of 0x7040 (28,736) characters of a value. | Static |
| Quoted-printable | `ENCODING=QUOTED-PRINTABLE` or a bare `QUOTED-PRINTABLE` parameter turns on the decoder (0x141304, 0x1fdee0). | Static |
| Name compare | 0x0c2240 compares a UTF-16 name with an ASCII token. It ignores the case. The length must be equal. | Static |

The parameters are split at `;` (0x13cc48), then at `=` (0x13ca74). A `TYPE=` value is split at `,` (0x13cb50). Thus `TYPE=HOME,WORK` and `TYPE=HOME;TYPE=WORK` both work. A parameter with no `=`, as in vCard 2.1 (`TEL;HOME:`), goes to the type handler.

A text value is not changed (0x1d13fc is an empty function). The field splitter 0x184bac does not split at `\;`, but it does not remove the backslash. Thus `\n`, `\,` and `\;` stay in the text. Cases C03 and K01 test this on the screen.

### The token tables

The parser compares each name with a token from two tables.

The vCard table at 0x4ffae4 has 30 tokens: `home work pref fax car pager cell note type vcard charset quoted-printable begin end fn n nickname adr add tel email url title org encoding macintosh x-mac-japanese photo jpeg base64`.

The iCalendar table at 0x4ffc9c has 60 tokens: `begin vcalendar vevent summary description location attendee organizer dtstart dtend duration rrule exrule xrule dalarm rdate exdate freq daily weekly monthly yearly interval count wkst byday bysetpos bymonthday byyearday bymonth byweekno cn value date period vtimezone vtodo tzid daylight standard tzoffsetfrom tzoffsetto valarm trigger date-time related end start until tz version 1.0 x-wr-calname prodid completed in-process cancelled due status priority`.

The day table at 0x4ffdc4 has `su mo tu we th fr sa`.

Each property is a C++ class. The vtable slot +0x1c reads the value. The slot +0x20 reads one `TYPE` value. The slot +0x24 reads one other parameter.

## Contacts

### The properties

The dispatcher 0x157af0 handles these properties. The iPod ignores all other properties, for example `BDAY`, `UID`, `IMPP`, `LABEL`, `X-ABLabel` and `CATEGORIES`.

| Property | Handler | Result |
|---|---|---|
| `BEGIN:VCARD`, `END:VCARD` | 0x170148 | The start and the end of a contact. |
| `N` | 0x157f78 | The first 3 fields: family name (+0xc), given name (+0x14), middle name (+0x1c). The prefix and the suffix are lost. |
| `FN` | 0x158020 | The full name (+0x24). |
| `NICKNAME` | 0x157df8 | The nickname. |
| `ORG` | 0x157e84 | Each field becomes one line (0x1499c0 joins the fields with LF). |
| `TITLE` | 0x157ab0 | The job title. |
| `TEL` | 0x157a04 | A phone number. Refer to the next table. |
| `EMAIL` | 0x1579b8 | An e-mail address. Types: `PREF`, `HOME`, `WORK` (0x151470). |
| `URL` | 0x158068 | A web address. The research did not examine the types of `URL`. |
| `ADR` | 0x157db4 | An address with 7 fields (0x17c764). Types: `PREF`, `HOME`, `WORK` (0x17c8c8). |
| `ADD` | 0x157e40 | An address with 7 fields in the opposite order (0x1db104). The research did not find a writer of this property. |
| `NOTE` | 0x157938 | The note (+0x4c). 0x223354 looks for the text `\n[Comments]\n`. |
| `PHOTO` | 0x157a48 | Refer to [The photo](#the-photo). |

A contact is kept only if it has `N`, `FN`, `NICKNAME`, `ORG` or `EMAIL`. Their handlers set the flag +0x74 (stores at 0x158014, 0x15805c, 0x157e34, 0x157eec and 0x1579f0). 0x157f10 tests the flag. A contact with only `TEL` is not kept. The load stops after 4000 contacts (0xd1fc4: count > 3999). It also stops if the free memory is less than 0x180000 bytes (0xc2720).

### The types of a phone number

0x15383c sets one bit for each type. `PREF` puts the number first in the list (0x1495fc).

| Type | Bit |
|---|---|
| `HOME` | 0x01 |
| `CELL` | 0x02 |
| `FAX` | 0x04 |
| `WORK` | 0x08 |
| `PAGER` | 0x10 |
| `CAR` | 0x20 |
| `PREF` | a separate flag |

The iPod ignores `VOICE`, `IPHONE`, `MAIN`, `OTHER` and `X-…`. The screen labels are at 0x4b26d0 to 0x4b275c: home, home fax, home mobile, home car, home pager, work, fax, mobile, car, pager, telephone, e-mail, web.

### The photo

- The parameter handler 0x153a3c accepts `ENCODING=BASE64`. Another `ENCODING` value, for example `b`, makes the photo not valid.
- The type handler 0x1539fc accepts `JPEG` and `BASE64`. Another type, for example `PNG`, makes the photo not valid.
- With no parameter, the photo is valid (0x153aa8 sets the flag to 1).
- 0x1539bc counts the base64 characters. 0x1496f4 records the file, the offset and the count. The iPod reads the photo from the file when it shows the contact.

macOS writes `PHOTO;ENCODING=b;TYPE=JPEG:`. The iPod does not show this photo. A vCard 4.0 `PHOTO:data:image/jpeg;base64,…` has no parameter. The iPod then reads `data:image/jpeg;base64,` as base64 text. Case C05 tests the result.

## Calendars

### The structure

| Component | Handler | Result |
|---|---|---|
| `VCALENDAR` | 0x18dfbc | Reads `BEGIN`, `TZ`, `VERSION`, `X-WR-CALNAME`, `PRODID`. |
| `VEVENT` | 0x18df48, properties 0x1dc600 | 0x236d28 adds the event to the list at calendar + 8. |
| `VTODO` | 0x18ded4, properties 0x1dc600 | 0x236adc adds the item to the list at calendar + 0x34. |
| `VTIMEZONE` | 0x18e1d8, properties 0x19ca4c | 0x236d48 adds the time zone. |
| `STANDARD`, `DAYLIGHT` | 0x19c9fc, properties 0x201d50 | Reads `DTSTART`, `TZOFFSETFROM`, `TZOFFSETTO`, `RRULE`, `RDATE`. |
| `VALARM` | 0x1dc480, properties 0x149cfc | Reads only `TRIGGER`. |
| Other nested component | 0x1dc480 → 0x1dc824 | Skipped. |

`VERSION:1.0` sets the vCalendar 1.0 mode (0x18e19c, calendar + 0x90). In this mode, `RRULE` uses the vCalendar 1.0 reader (0x1fe5e4). `X-WR-CALNAME` goes to calendar + 0x7c (0x18e310). Case K10 shows the name of a calendar without `X-WR-CALNAME`.

### The properties of an event and of a to-do item

The dispatcher 0x1dc600 handles these properties. The iPod ignores all other properties, for example `UID`, `RECURRENCE-ID`, `DTSTAMP`, `SEQUENCE`, `TRANSP`, `CLASS`, `CATEGORIES`, `URL` and `X-…`.

| Property | Handler | Note |
|---|---|---|
| `SUMMARY` | 0x1dc0c0 | |
| `DESCRIPTION` | 0x1dc29c | |
| `LOCATION` | 0x1dc1b4 | |
| `ATTENDEE` | 0x1dc1f0 | The parameter `CN` gives the name. 0x1f809c removes the quotes. |
| `ORGANIZER` | 0x1dc220 | |
| `DTSTART` | 0x1dc024 | Refer to [Dates and times](#dates-and-times). |
| `DTEND` | 0x1dbbf4 | |
| `DURATION` | 0x1dc168 | 0xf23fc reads the value. The end is the start plus the duration. |
| `RRULE` | 0x1dc364 | Refer to [Repeated events](#repeated-events). |
| `EXRULE` | 0x1dc2d8 | |
| `RDATE` | 0x1dc3d4 | |
| `EXDATE` | 0x1dc314 | A list of date-times. `VALUE=DATE` and `VALUE=PERIOD` make the property not valid (0x1f8c68). |
| `DALARM` | 0x1dc0fc | vCalendar 1.0 alarm. |
| `BEGIN:VALARM` | 0x1dc480 | `TRIGGER` reads `VALUE=DATE-TIME` and `RELATED=START` or `END` (0x183018). |
| `DUE` | 0x1dc5c8 | To-do items. |
| `STATUS` | 0x1dc6a0 | `COMPLETED` 2, `IN-PROCESS` 3, `CANCELLED` 4. Other values keep the default ("Needs Action"). |
| `PRIORITY` | 0x167f80 | |

The token `xrule` (0x13) has a handler (0x1dc424). It is the same text as the end of `exrule`. No standard writer uses it.

### Dates and times

- 0xc8e24 reads 4 digits for the year, 2 for the month and 2 for the day. If a `T` follows, it reads 2 digits each for the hours, the minutes and the seconds. A `Z` at the end marks UTC.
- The extended form, for example `2026-11-10T12:00:00`, does not parse correctly. Case K04 tests it.
- A value with no `T` is a date at 00:00. The parser does not read `VALUE=DATE` for `DTSTART` and `DTEND`. Case K05 shows how the iPod shows an all-day event.
- `TZID=` (0x18e938) gives the name of a time zone. 0x1dc264 looks for a `VTIMEZONE` with this name in the same calendar (0x2571fc). If there is no match, the event keeps no time zone. Case K03 tests both.
- `TZ:` in vCalendar 1.0 sets the zone of the calendar (0x18e270).

### Repeated events

0x1f2014 reads the parts of an iCalendar 2.0 `RRULE`:

| Part | Result |
|---|---|
| `FREQ` | `DAILY` 4, `WEEKLY` 5, `MONTHLY` 6, `YEARLY` 7 (0x1f1be0). `SECONDLY`, `MINUTELY` and `HOURLY` are not in the table. Case K06f tests them. |
| `INTERVAL` | + 0x1c |
| `COUNT` | + 0x20 |
| `UNTIL` | 0x1f1a2c |
| `WKST` | + 0x24 (0x1f1d44) |
| `BYDAY` | 0x1f19bc. 0x1f1d44 reads an optional sign, a number and a two-letter day. |
| `BYSETPOS` | 0x1f1f98 |
| `BYMONTH` | 0x1f1a90 |
| `BYWEEKNO` | 0x1f1e2c |
| `BYMONTHDAY` | 0x1f1c60 |
| `BYYEARDAY` | 0x1f1b84 |

`BYHOUR`, `BYMINUTE` and `BYSECOND` are not in the table.

The iPod ignores `RECURRENCE-ID`. A moved occurrence from macOS thus shows two times: one time at the old place (from the series) and one time at the new place. Case K12 tests it.

## The iPod dialect

The translation layer must write files that obey these rules. The rules come from the static research. The emulator test can change some of them.

### All files

1. Start each file with the UTF-8 BOM `EF BB BF`.
2. Use CRLF at each line end.
3. Fold a line longer than 75 bytes. Start each continuation line with one space.
4. Do not write `\n`, `\,` or `\;` in a text. Replace a line break with a space or with " / " until case C07 shows that quoted-printable line breaks work. Replace `;` in a field of `N`, `ADR` or `ORG` with `,`.
5. Write only the properties in the tables of this note.

### Contacts

1. Write one file, `Contacts/iPodFirm Contacts.vcf`, with all contacts. Use the marker `iPodFirm` in the name, so that the app removes only its own files.
2. Write `VERSION:3.0`.
3. Write `N` with three fields: family name, given name, middle name. Put the prefix and the suffix only in `FN`.
4. Write `FN` for each contact. For a company card, write `ORG` and `FN` with the company name.
5. Write `TEL;TYPE=…` with only `HOME`, `WORK`, `CELL`, `FAX`, `PAGER`, `CAR` and `PREF`. Map iPhone and mobile to `CELL`. Map main and other to no type.
6. Write `EMAIL;TYPE=…` and `ADR;TYPE=…` with only `HOME`, `WORK` and `PREF`.
7. Write the photo as `PHOTO;ENCODING=BASE64;TYPE=JPEG:`. Encode the image again as a small JPEG.
8. Optionally, add the birthday and the other dates, the related names and the instant message addresses to `NOTE`.
9. Do not write more than 4000 contacts.

### Calendars

1. Write one file for each calendar: `Calendars/iPodFirm <calendar title>.ics`. Remove the characters that FAT does not accept.
2. Write `VERSION:2.0` and `X-WR-CALNAME:<calendar title>`.
3. Write the dates in the basic form. Write the times in UTC with `Z`, or as floating local times. Cases K01 to K03 decide which form is correct on the iPod.
4. Expand the repeated events in a date window, for example 30 days before today and 365 days after today. Write each occurrence as one event with no `RRULE`. EventKit gives the occurrences, with the moved occurrences and without the deleted occurrences. This removes the problems of `RECURRENCE-ID` and `EXDATE`.
5. Write an all-day event with `DTSTART;VALUE=DATE` and `DTEND;VALUE=DATE`, if case K05 shows the event correctly.
6. Write each alarm as `BEGIN:VALARM`, `TRIGGER:-PT<n>M`, `END:VALARM`.
7. Write the reminders as `VTODO` with `SUMMARY`, `DUE`, `PRIORITY` and `STATUS:COMPLETED` or `STATUS:NEEDS-ACTION`.
8. Write `ATTENDEE;CN=<name>:mailto:<address>` with no quotes, if the name has no `;`, `:` or `,`.

## The macOS side

| Item | Value |
|---|---|
| Contacts | `CNContactStore` gives the contacts. `CNContactVCardSerialization` writes vCard 3.0 in UTF-8 with no BOM, with `item1.` groups, `X-ABLabel` lines, escapes, and `PHOTO;ENCODING=b;TYPE=JPEG`. Thus the app must write its own vCard text. |
| Calendars | `EKEventStore` gives the calendars and the events. EventKit has no function that writes an `.ics` file. The app must write the iCalendar text. `events(matching:)` with a date predicate gives the occurrences of the repeated events. |
| Reminders | `EKEventStore` with the entity type `.reminder` gives the reminders. |
| Info.plist | `NSContactsUsageDescription`, `NSCalendarsFullAccessUsageDescription` and `NSRemindersFullAccessUsageDescription`. `mac/scripts/build-app.sh` writes the Info.plist. |
| Signature | The app uses the hardened runtime. It then needs the entitlements `com.apple.security.personal-information.addressbook` and `com.apple.security.personal-information.calendars`. Today `build-app.sh` signs with no entitlements file. |
| Write to the iPod | The app writes files to the mounted iPod volume. `PlaylistFolders.write(volume:)` is an example. |

The values in this table come from the Apple documentation. The research did not test them on macOS 27.

## The design of the translation layer

The layer is a Mac function. It needs no firmware patch, because the stock parser has the necessary features.

1. `IPodFWKit/PIMExport.swift` has a contact model, an event model and two writers: `VCardWriter` and `ICalWriter`. The writers obey [The iPod dialect](#the-ipod-dialect). They use no Apple framework, so that unit tests can compare their output with fixed text.
2. A reader in the app target fills the models from `CNContactStore` and `EKEventStore`.
3. A sync function removes the old `iPodFirm …` files in `/Contacts` and `/Calendars`, and writes the new files. It does not touch the other files.
4. The user interface has a list of the calendars, the reminder lists and the contact groups, a date window, and a **Sync** button. It shows the count of contacts and of events, and a warning above 4000 contacts.
5. The app asks for the access to Contacts, Calendars and Reminders only when the user opens this function.

The owner decides on the build after the emulator test.

## Emulator test

The script [calendar-contacts/make_test.py](calendar-contacts/make_test.py) makes a drive with the stock firmware, 14 contact cases and 12 calendar cases. Each case is one file. The name of each contact and each event starts with the case number. The events are in the week of 9 November 2026.

Static expectations:

| Case | File | Test | Expected result |
|---|---|---|---|
| C01 | `C01.vcf` | UTF-8 with a BOM, accented letters | Correct name |
| C02 | `C02.vcf` | UTF-8 without a BOM | Wrong accented letters (Latin-1 or Mac Roman) |
| C03 | `C03.vcf` | macOS export form | Name, nickname, org, title, phones, e-mails, address and URL show. The note shows the backslashes. No photo. |
| C04 | `C04.vcf` | Photo with `ENCODING=BASE64` | The photo shows |
| C05 | `C05.vcf` | vCard 4.0 | Name and e-mail show. Phone shows `tel:` in the number. Photo not correct. |
| C06 | `C06.vcf` | Folded lines | `C06 Folded`; the note joins correctly |
| C07 | `C07.vcf` | vCard 2.1, quoted-printable | Phones show. Note: unknown if the line break shows. |
| C08 | `C08.vcf` | Only `ORG` and `FN` | The contact shows |
| C09 | `C09.vcf` | Only `TEL` and `EMAIL` | A contact with no name shows, because `EMAIL` sets the flag |
| C10 | `C10.vcf` | UTF-16 little-endian with a BOM | Correct name |
| C11 | `C11.vcf` | 3 contacts in one file | 3 contacts |
| C12 | `C12.vcf` | CJK name | Depends on the fonts of the language |
| C13 | `C13.txt` | Extension `.txt` | The contact shows |
| C14 | `Sub/C14.vcf` | A subfolder | Unknown |
| K01 | `K01.ics` | Floating time | 10 November, 10:00 |
| K02 | `K02.ics` | UTC time | 15:00 UTC in the time zone of the iPod |
| K03 | `K03.ics` | TZID with and without a VTIMEZONE | K03a at 09:00 New York time. K03b: unknown. |
| K04 | `K04.ics` | Extended date form | Wrong date or no event |
| K05 | `K05.ics` | All-day events | Unknown |
| K06 | `K06.ics` | Repeat rules | a to e and g correct. f (hourly): unknown. |
| K07 | `K07.ics` | Exceptions | K07a has no event on 11 November. K07b has an event on 11 November. |
| K08 | `K08.ics` | Alarms | Alarm marks on both events |
| K09 | `K09.ics` | To-do items | Two items, one completed |
| K10 | `K10 File Name.ics` | No `X-WR-CALNAME` | Unknown name |
| K11 | `K11.vcs` | vCalendar 1.0 | Three Tuesdays at 11:00 |
| K12 | `K12.ics` | macOS export form | The moved occurrence shows two times |

Results: not tested yet.

## Open questions

- The condition of the sample files (0x1ec028). Does the iPod write them again after the app removes them?
- The meaning of the two values of the directory entry in 0x10f0c0. They are possibly the Mac file type and creator.
- The size limit of a photo, and the size of the photo on the screen.
- The memory that one event uses. This gives the maximum date window.
- The reload after the disk mode (0x1eaf5c).
- The real iPod.
