"""Make an emulator drive to test the stock Contacts and Calendars readers (no patches).

usage: uv run python -I re/calendar-contacts/make_test.py
The profile goes to $PF_WORK/calendar-contacts/profile (default /tmp/pf-work).
Each test case is one file. The name of the contact or of the event starts with the case number.
Refer to re/calendar-contacts.md for the expected result of each case.
"""
import base64
import io
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "playlist-folders/harness"))
import emu  # noqa: E402

BOM = b"\xef\xbb\xbf"


def crlf(text: str) -> str:
    """Join the lines with CRLF, as RFC 2425 and RFC 5545 tell."""
    return "\r\n".join(text.strip("\n").split("\n")) + "\r\n"


def utf8(text: str, bom: bool = True) -> bytes:
    return (BOM if bom else b"") + crlf(text).encode("utf-8")


def jpeg_b64() -> str:
    """A red 40 x 40 JPEG as base64, for the photo cases."""
    from PIL import Image
    buf = io.BytesIO()
    Image.new("RGB", (40, 40), (220, 30, 30)).save(buf, "JPEG", quality=80)
    return base64.b64encode(buf.getvalue()).decode()


def fold(line: str, width: int = 74) -> str:
    """Fold a long line: each next part starts with one space."""
    parts = [line[i:i + width] for i in range(0, len(line), width)]
    return "\n ".join(parts)


PHOTO = jpeg_b64()

CONTACTS: dict[str, bytes] = {
    # C01: the stock form (vCard 3.0, lower case), UTF-8 with a BOM, accented letters
    "C01.vcf": utf8("""begin:vcard
version:3.0
n:Ångström;C01 Zoë;;;
fn:C01 Zoë Ångström
tel;type=home:111-0101
end:vcard"""),
    # C02: the same text, UTF-8 without a BOM
    "C02.vcf": utf8("""BEGIN:VCARD
VERSION:3.0
N:Ångström;C02 Zoë;;;
FN:C02 Zoë Ångström (no BOM)
END:VCARD""", bom=False),
    # C03: the form of a macOS Contacts export (group prefixes, X-AB labels, escapes, ENCODING=b photo)
    "C03.vcf": utf8(f"""BEGIN:VCARD
VERSION:3.0
PRODID:-//Apple Inc.//macOS 27.2//EN
N:Macexport;C03 Mac;Middle;Dr.;Jr.
FN:C03 Mac Middle Macexport
NICKNAME:Macky
ORG:Example Corp;Research
TITLE:Engineer
item1.EMAIL;type=INTERNET;type=pref:c03@example.com
item1.X-ABLabel:_$!<Other>!$_
EMAIL;type=INTERNET;type=WORK:c03.work@example.com
TEL;type=CELL;type=VOICE;type=pref:111-0301
TEL;type=IPHONE;type=CELL;type=VOICE:111-0302
TEL;type=HOME;type=FAX:111-0303
TEL;type=MAIN:111-0304
item2.ADR;type=HOME;type=pref:;;1 Main Street;Springfield;CA;90001;United States
item2.X-ABADR:us
item3.URL;type=pref:https://example.com
item3.X-ABLabel:_$!<HomePage>!$_
NOTE:Line one\\nLine two\\, with comma\\; and semicolon
BDAY:1990-01-02
X-ABUID:00000000-0000-0000-0000-000000000003:ABPerson
UID:00000000-0000-0000-0000-000000000003
{fold("PHOTO;ENCODING=b;TYPE=JPEG:" + PHOTO)}
END:VCARD"""),
    # C04: as C03 but the photo has ENCODING=BASE64
    "C04.vcf": utf8(f"""BEGIN:VCARD
VERSION:3.0
N:Photobase64;C04;;;
FN:C04 Photobase64
TEL;type=WORK:111-0401
{fold("PHOTO;ENCODING=BASE64;TYPE=JPEG:" + PHOTO)}
END:VCARD"""),
    # C05: vCard 4.0 (URI values, a data URI photo)
    "C05.vcf": utf8(f"""BEGIN:VCARD
VERSION:4.0
N:Version4;C05;;;
FN:C05 Version4
TEL;VALUE=uri;TYPE=cell:tel:+1-555-0501
EMAIL;TYPE=work:c05@example.com
{fold("PHOTO:data:image/jpeg;base64," + PHOTO)}
END:VCARD"""),
    # C06: folded lines in the name and in a long note
    "C06.vcf": utf8("""BEGIN:VCARD
VERSION:3.0
N:Folded;C06;;;
FN:C06 Fol
 ded
NOTE:This note is longer than one line. It continues on a folded line that st
 arts with one space. The two parts must join with no space between "st" and
  "arts".
END:VCARD"""),
    # C07: vCard 2.1 (bare types, quoted-printable with a CRLF, CHARSET=UTF-8)
    "C07.vcf": utf8("""BEGIN:VCARD
VERSION:2.1
N;CHARSET=UTF-8:Twoone;C07 Zoë
FN;CHARSET=UTF-8:C07 Zoë Twoone
TEL;HOME;VOICE:111-0701
TEL;WORK;FAX:111-0702
NOTE;ENCODING=QUOTED-PRINTABLE:Line one=0D=0ALine two =C3=A9
END:VCARD"""),
    # C08: only ORG (a company card)
    "C08.vcf": utf8("""BEGIN:VCARD
VERSION:3.0
N:;;;;
FN:C08 Company Only
ORG:C08 Company Only;
X-ABShowAs:COMPANY
END:VCARD"""),
    # C09: no N, no FN, no ORG (EMAIL alone keeps the contact)
    "C09.vcf": utf8("""BEGIN:VCARD
VERSION:3.0
TEL:111-0901
EMAIL:c09@example.com
END:VCARD"""),
    # C10: UTF-16 little-endian with a BOM
    "C10.vcf": b"\xff\xfe" + crlf("""BEGIN:VCARD
VERSION:3.0
N:Utfsixteen;C10 Zoë;;;
FN:C10 Zoë Utfsixteen
END:VCARD""").encode("utf-16-le"),
    # C11: three contacts in one file
    "C11.vcf": utf8("\n".join(f"""BEGIN:VCARD
VERSION:3.0
N:Multi;C11 {i};;;
FN:C11 {i} Multi
END:VCARD""" for i in "ABC")),
    # C12: CJK name, UTF-8 with a BOM
    "C12.vcf": utf8("""BEGIN:VCARD
VERSION:3.0
N:山田;C12 太郎;;;
FN:C12 山田 太郎
END:VCARD"""),
    # C13: a file with the extension .txt
    "C13.txt": utf8("""BEGIN:VCARD
VERSION:3.0
N:Textfile;C13;;;
FN:C13 Textfile
END:VCARD"""),
    # C14: a file in a subfolder
    "Sub/C14.vcf": utf8("""BEGIN:VCARD
VERSION:3.0
N:Subfolder;C14;;;
FN:C14 Subfolder
END:VCARD"""),
}

VTZ_NY = """BEGIN:VTIMEZONE
TZID:America/New_York
BEGIN:DAYLIGHT
TZOFFSETFROM:-0500
RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU
DTSTART:20070311T020000
TZNAME:EDT
TZOFFSETTO:-0400
END:DAYLIGHT
BEGIN:STANDARD
TZOFFSETFROM:-0400
RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU
DTSTART:20071104T020000
TZNAME:EST
TZOFFSETTO:-0500
END:STANDARD
END:VTIMEZONE"""


def cal(name: str | None, body: str, version: str = "2.0") -> bytes:
    head = f"BEGIN:VCALENDAR\nVERSION:{version}\nPRODID:-//iPodFirm//calendar-contacts test//EN\n"
    if name:
        head += f"X-WR-CALNAME:{name}\n"
    return utf8(head + body.strip("\n") + "\nEND:VCALENDAR")


def event(summary: str, start: str, end: str, extra: str = "") -> str:
    return f"BEGIN:VEVENT\nSUMMARY:{summary}\nDTSTART{start}\nDTEND{end}\n{extra}END:VEVENT\n"


CALENDARS: dict[str, bytes] = {
    # K01: floating time, location and description, UTF-8 with a BOM
    "K01.ics": cal("K01 Basic", event("K01 Floating 10:00 Zoë", ":20261110T100000", ":20261110T110000",
                                      "LOCATION:Room 1\nDESCRIPTION:Floating time\\, no zone\n")),
    # K02: UTC time (Z)
    "K02.ics": cal("K02 UTC", event("K02 UTC 15:00Z", ":20261110T150000Z", ":20261110T160000Z")),
    # K03: TZID with a VTIMEZONE, and a TZID with no VTIMEZONE
    "K03.ics": cal("K03 TZID", VTZ_NY + "\n"
                   + event("K03a New York 09:00", ";TZID=America/New_York:20261110T090000",
                           ";TZID=America/New_York:20261110T100000")
                   + event("K03b Unknown zone 09:00", ";TZID=Europe/Nowhere:20261110T090000",
                           ";TZID=Europe/Nowhere:20261110T100000")),
    # K04: the extended form of the date and time
    "K04.ics": cal("K04 Extended", event("K04 Extended 12:00", ":2026-11-10T12:00:00", ":2026-11-10T13:00:00")),
    # K05: all-day events (one day, three days)
    "K05.ics": cal("K05 All day", event("K05a All day", ";VALUE=DATE:20261111", ";VALUE=DATE:20261112")
                   + event("K05b Three days", ";VALUE=DATE:20261111", ";VALUE=DATE:20261114")),
    # K06: recurrences
    "K06.ics": cal("K06 Repeat",
                   event("K06a Daily x5", ":20261109T080000", ":20261109T083000", "RRULE:FREQ=DAILY;COUNT=5\n")
                   + event("K06b Mo-We-Fr until 30 Nov", ":20261109T120000", ":20261109T123000",
                           "RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20261130T235959Z\n")
                   + event("K06c Monthly day 15", ":20261115T090000", ":20261115T093000",
                           "RRULE:FREQ=MONTHLY;BYMONTHDAY=15\n")
                   + event("K06d Monthly 2nd Tuesday", ":20261110T140000", ":20261110T143000",
                           "RRULE:FREQ=MONTHLY;BYDAY=2TU\n")
                   + event("K06e Yearly", ":20261112T070000", ":20261112T073000", "RRULE:FREQ=YEARLY\n")
                   + event("K06f Hourly x3", ":20261113T100000", ":20261113T101000", "RRULE:FREQ=HOURLY;COUNT=3\n")
                   + event("K06g Every 2 weeks Tu", ":20261110T160000", ":20261110T163000",
                           "RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=TU;COUNT=4\n")),
    # K07: exceptions (date-time form and VALUE=DATE form)
    "K07.ics": cal("K07 Except",
                   event("K07a Daily, no 11 Nov", ":20261109T180000", ":20261109T183000",
                         "RRULE:FREQ=DAILY;COUNT=5\nEXDATE:20261111T180000\n")
                   + event("K07b All day daily, no 11 Nov", ";VALUE=DATE:20261109", ";VALUE=DATE:20261110",
                           "RRULE:FREQ=DAILY;COUNT=5\nEXDATE;VALUE=DATE:20261111\n")),
    # K08: alarms
    "K08.ics": cal("K08 Alarm",
                   event("K08a Alarm 15 min before", ":20261110T200000", ":20261110T203000",
                         "BEGIN:VALARM\nACTION:DISPLAY\nDESCRIPTION:Reminder\nTRIGGER:-PT15M\nEND:VALARM\n")
                   + event("K08b Alarm absolute", ":20261110T210000", ":20261110T213000",
                           "BEGIN:VALARM\nACTION:AUDIO\nTRIGGER;VALUE=DATE-TIME:20261110T205500Z\nEND:VALARM\n")),
    # K09: to-do items
    "K09.ics": cal("K09 To Do",
                   "BEGIN:VTODO\nSUMMARY:K09a To do, due 12 Nov\nDUE:20261112T170000\nPRIORITY:1\n"
                   "STATUS:NEEDS-ACTION\nEND:VTODO\n"
                   "BEGIN:VTODO\nSUMMARY:K09b To do, completed\nSTATUS:COMPLETED\nPRIORITY:5\nEND:VTODO\n"),
    # K10: no X-WR-CALNAME (the calendar name comes from where?)
    "K10 File Name.ics": cal(None, event("K10 No calendar name", ":20261110T073000", ":20261110T080000")),
    # K11: vCalendar 1.0
    "K11.vcs": cal(None, "TZ:-05\n" + event("K11 vCal 1.0 weekly", ":20261110T110000", ":20261110T113000",
                                             "RRULE:W1 TU #3\nDALARM:20261110T105500\n"), version="1.0"),
    # K12: the form of a macOS Calendar export (UID, DTSTAMP, X-APPLE, RECURRENCE-ID, ATTENDEE)
    "K12.ics": cal("K12 Mac export", VTZ_NY + """
BEGIN:VEVENT
UID:K12-SERIES@example.com
DTSTAMP:20261105T120000Z
CREATED:20261101T120000Z
LAST-MODIFIED:20261105T120000Z
SEQUENCE:1
SUMMARY:K12a Weekly series
DTSTART;TZID=America/New_York:20261109T130000
DTEND;TZID=America/New_York:20261109T140000
RRULE:FREQ=WEEKLY;COUNT=3
TRANSP:OPAQUE
X-APPLE-TRAVEL-ADVISORY-BEHAVIOR:AUTOMATIC
ORGANIZER;CN="Org Person":mailto:org@example.com
ATTENDEE;CN="Ann Attendee";CUTYPE=INDIVIDUAL;PARTSTAT=ACCEPTED;ROLE=REQ-PARTICIPANT;EMAIL=ann@example.com:mailto:ann@example.com
BEGIN:VALARM
X-WR-ALARMUID:00000000-0000-0000-0000-0000000000A1
UID:00000000-0000-0000-0000-0000000000A1
TRIGGER:-PT10M
ACTION:DISPLAY
DESCRIPTION:Reminder
X-APPLE-DEFAULT-ALARM:TRUE
ACKNOWLEDGED:20261105T120000Z
END:VALARM
END:VEVENT
BEGIN:VEVENT
UID:K12-SERIES@example.com
RECURRENCE-ID;TZID=America/New_York:20261116T130000
DTSTAMP:20261105T120000Z
SUMMARY:K12b Moved occurrence
DTSTART;TZID=America/New_York:20261116T150000
DTEND;TZID=America/New_York:20261116T160000
END:VEVENT
"""),
}


def write(root: Path, files: dict[str, bytes]):
    for rel, data in files.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)


if __name__ == "__main__":
    prof = emu.build("calendar-contacts", [])
    work = emu.WORK / "calendar-contacts"
    for folder, files in (("Contacts", CONTACTS), ("Calendars", CALENDARS)):
        root = work / folder
        write(root, files)
        subprocess.run([emu.TOOLS / "ipod-boot", "put-files", prof / "drives/ipodfirm-custom.img", root, f"/{folder}"],
                       check=True, capture_output=True)
    print(prof)
