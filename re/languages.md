# The languages of osos 1.3

This note tells how RetailOS 1.3 selects the language of the text. It also gives a method for a patch to show its text in the current language. The method is for the document [docs/translations.md](../docs/translations.md).

Offsets are osos file offsets. The CPU address is the same. All results are static (Ghidra and a read of the image). No result is tested in the emulator or on the real iPod yet.

## Summary

- The settings key 0x6062 holds the language. Its value is the key of the selected Language menu item, 0x6063–0x607b.
- `FUN_00192ca8()` returns this value. The firmware calls it for its own language decisions.
- A table at 0x2a9a74 gives a locale name and a four-character code for each value.
- At the start, the firmware makes one string provider for each language block. It registers each provider with its four-character code.
- The current provider is the provider of the current code. The firmware asks that provider first, then the English main block.
- Thus a patch can call `FUN_00192ca8()` and select its text from a table with 25 entries.

## The setting

| Address | Function |
|---|---|
| 0x192ca8 | Returns the language key. It gets the settings object (0x193090), then calls its method + 0xa8 with the key 0x6062 and the operation `prID`. If no value is set, it returns 0x6063 (English). |
| 0x193090 | Returns the settings object: `FUN_001d3050(0x6000)`. |
| 0x1d3050 | Finds an object by its key in the object map. It returns 0 if the object does not exist. |
| 0x190a9c | Finds the language record of the current key in the table at 0x2a9a74. If no record agrees, it returns 0x1087081c. |
| 0x190a84 | Returns the four-character code of the current record (record + 8). A method table at 0x4fd0a8 points to it. |

The firmware uses `FUN_00192ca8()` in other places. Examples:

- 0x149a3c returns 1 for Japanese, Korean and the two Chinese languages (0x606d, 0x606e, 0x6074, 0x6075).
- 0x1705dc gives a number for each of these four languages: 6, 9, 8 and 7. It gives 1 for all other languages.
- 0x1b9dd8 makes a view again when the language is different from the language at + 0x7e.

## The language records

The table at 0x2a9a74 has records of 12 bytes. A record with the key 0 ends the table.

| Offset | Content |
|---|---|
| +0 | i16: the language key (the Language menu item) |
| +4 | Pointer to the locale name, for example "da-DK" |
| +8 | Four-character code, for example `daDK`. English has 0. |

| Key | Locale name | Code | Block | In the Language menu |
|---|---|---|---|---|
| 0x6063 | en-US | 0 | 24 (main) | Yes: English |
| 0x6064 | da-DK | `daDK` | 1 | Yes: Dansk |
| 0x6065 | de-CH | `deCH` | 2 | No |
| 0x6066 | de-DE | `deDE` | 3 | Yes: Deutsch |
| 0x6067 | es-ES | `esES` | 5 | Yes: Español |
| 0x6068 | fi-FI | `fiFI` | 6 | Yes: Suomi |
| 0x6069 | fr-BE | `frBE` | 7 | No |
| 0x606a | fr-CH | `frCH` | 8 | No |
| 0x606b | fr-FR | `frFR` | 9 | Yes: Français |
| 0x606c | it-IT | `itIT` | 11 | Yes: Italiano |
| 0x606d | ja-JP | `jaJP` | 12 | Yes: 日本語 |
| 0x606e | ko-KR | `koKR` | 13 | Yes: 한글 |
| 0x606f | nl-BE | `nlBE` | 14 | No |
| 0x6070 | nl-NL | `nlNL` | 15 | Yes: Nederlands |
| 0x6071 | no-NO | `noNO` | 16 | Yes: Norsk |
| 0x6072 | pt-PT | `ptPT` | 18 | Yes: Português |
| 0x6073 | sv-SE | `svSE` | 20 | Yes: Svenska |
| 0x6074 | zh-CN | `zhCN` | 22 | Yes: 简体中文 |
| 0x6075 | zh-TW | `zhTW` | 23 | Yes: 繁體中文 |
| 0x6076 | csCZ | `csCZ` | 0 | Yes: Čeština |
| 0x6077 | elGR | `elGR` | 4 | Yes: Ελληνικά |
| 0x6078 | huHU | `huHU` | 10 | Yes: Magyar |
| 0x6079 | plPL | `plPL` | 17 | Yes: Polski |
| 0x607a | ruRU | `ruRU` | 19 | Yes: Русский |
| 0x607b | trTR | `trTR` | 21 | Yes: Türkçe |

Apple wrote the last six locale names without a hyphen. The names are at 0x6788e1–0x678975.

## The Language menu

The Language menu has 21 items (data from 0x4afe24). The item keys are 0x60006063–0x6000607b, but the keys 0x6065, 0x6069, 0x606a and 0x606f are not in the menu. The main block also has no name string for these four keys.

The blocks 2, 7, 8 and 14 hold only 60 strings: the month names, the day names and the date formats. No menu item selects them. Thus a translator does not need them, and a patch can use the text of the main language for them.

## The blocks and the providers

The firmware has two tables in the image:

| Address | Content |
|---|---|
| 0x2aad9c | 24 four-character codes in alphabetical order: `csCZ`, `daDK`, `deCH` … `zhTW`. |
| 0x2aad3c | 24 sizes, one for each language block. |
| 0x69cce4 | 24 pointers to the language blocks, in the same order. Block *n* is at entry *n*. No code refers to this address directly. 0xc96d0 gives the RAM address 0x1081ea40. |

Thus the block number is the position of the code in the alphabetical list. The block order in [the iPod languages](../docs/translations.md#the-ipod-languages) comes from this list.

At the start, 0x1d3160 makes the resource objects:

1. 0x140404 makes a provider for the main block (0x331da0). It writes it to 0x1081ea34 + 4.
2. 0x140404 makes a provider for each of the 24 language blocks (0x1406fc, the block pointer and the size). It writes them to the RAM table 0x10883c4c.
3. 0x1aeaa0 makes the root object. It registers the main provider.
4. 0x152a6c makes the language manager (vtable 0x668f1c). The root object is its parent (+ 0x10).
5. 0x14047c registers each language provider with its code (method + 0x74, 0x1ae99c). The manager keeps the code-to-provider map at + 0x14.

The method + 0x6c of the manager (0x1529d4) selects a language. It calls 0x1aea64, which writes the code to + 0x3c and the provider to + 0x40. For English the code is 0, thus the provider is 0. Then 0x1529d4 reads the date formats (`LDTm` 128) of the new language.

The method + 0x5c of the manager (0x1528cc) answers a lookup. The general lookup 0x21f254 calls it first. For the ID 0xa9 it gives the 24-hour clock flag at + 0x4c4. For all other IDs it calls 0x1ae9d4. If + 0x40 has a provider, 0x1ae9d4 asks it (0x1405ac). If the provider does not have the resource, 0x21f254 continues with the parent, the root object. The root object has the main block. Its code is `MAIN`.

Thus a string that a language block does not have comes from the English main block. A language block cannot point to a different language block.

The method + 0x60 (0x1528f4) sets a property. For the ID 0xa9 it changes the 24-hour clock flag and reads the date formats again. For other IDs it writes the value into the current provider (0x1aea0c, 0x140614).

## The method for a patch

A patch answers a string lookup for its own ID in its hook of 0x21f254 (for example `hook_lookup` in [shuffle_album_mix.c](../patches/shuffle-album-mix/shuffle_album_mix.c)). The patch can select the text there:

1. Call `FUN_001d3050(0x6000)`. If the result is 0, use the English text. The settings object does not exist yet.
2. Call `FUN_00192ca8()`. Subtract 0x6063 to get an index from 0 to 24.
3. If the index is in the range and the table has a text for it, use that text. Else use the English text.

CAUTION: Do the step 1 before the step 2. `FUN_00193090` returns 0 if the settings object does not exist, and `FUN_00192ca8` then reads from address 0 + 0xa8.

Example:

```c
void *find_object(unsigned key);                                                /* 0x1d3050 */
int language_key(void);                                                         /* 0x192ca8 */

#define LANG_FIRST 0x6063                                                       /* English */
#define LANG_COUNT 25                                                           /* 0x6063-0x607b */
#define LANG(key)  ((key) - LANG_FIRST)

/* The text for the current language. Entry 0 is English. An empty entry uses English. */
static const char *pick(const char *const *texts)
{
    unsigned i;
    if (!find_object(0x6000))
        return texts[0];
    i = (unsigned)(language_key() - LANG_FIRST);
    return i < LANG_COUNT && texts[i] ? texts[i] : texts[0];
}

static const char *const mix_texts[LANG_COUNT] = {
    [LANG(0x6063)] = "Album Mix",
    /* [LANG(0x6066)] = "...", German; add the received translations here. */
};
```

The variant keys 0x6065, 0x6069, 0x606a and 0x606f are not in the menu. To be safe, a patch can give them the text of de-DE, fr-FR and nl-NL.

The fonts: Japanese, Korean, Greek, Russian and the two Chinese languages have their own `Type` resources in their blocks. Blocks 22 and 23 also have `View` resources. The label of a patch uses the `Type` of its row. Thus a UTF-8 text in the script of the current language must show correctly. This is not tested.

## Open questions

- Is a call of `FUN_00192ca8()` safe in the lookup hook and in the settings "get" hook? The method + 0xa8 of the settings object must not call the hook again for the same ID. A test in the emulator can answer this. Select a language on the first Language screen, then open a screen with a patch label.
- Which code calls the method + 0x6c after a selection in the Language menu? This research did not find the caller.
- Does a list show the new text at once after a language change? The note in [dark-theme.md](dark-theme.md) says that a language change does not make the screens again.
- Can the iPod select the blocks 2, 7, 8 and 14 in another way, for example from a region setting or from iTunes? No code for this was found.
