# Translations

Some patches add new text to the iPod, for example a menu item or a setting value. At this time, this text is in English only. The iPod shows the English text in all languages.

This document lists each text that needs a translation. If you speak one of the iPod languages, you can help. You do not need to know how to write code.

## How to help

1. Find your language in the table [The iPod languages](#the-ipod-languages).
2. Copy the [translation template](#translation-template).
3. Write your translation after each English text.
4. Use the words that Apple uses on the iPod. The table [Apple words on the iPod](#apple-words-on-the-ipod) gives some of them.
5. Open an issue or a pull request on GitHub. Put the language name in the title, for example "Translation: German".

You can translate only some of the texts. A partial translation also helps.

## Rules for translators

- Keep each text short. A row on the iPod screen shows approximately 20 characters. Longer text gets cut.
- Use the same capital letters as the Apple menus in your language. For example, German uses "Hauptmenü", and Swedish uses "Huvudmeny".
- Do not translate "USB-C", "kHz" or the numbers. Use the decimal mark of your language, for example "44,1 kHz".
- Keep the colon in "USB-C Audio: Off". Change the space before the colon only if your language needs it, for example French.
- Use the same word for the same item each time.
- If Apple has a word for the item in your language, use it. For example, use the Apple word for "Off" in a setting.

## The iPod languages

The firmware has 25 resource blocks. Block 24 holds the English text. Blocks 2, 7, 8 and 14 (Swiss German, Belgian French, Swiss French and Belgian Dutch) hold only date formats. The Language menu does not select them, so they do not need a translation.

The language key is the value of the iPod setting. A patch uses it to select the text. For the details, refer to [re/languages.md](../re/languages.md).

| Block | Language | Language key | Code |
|---|---|---|---|
| 0 | Czech | 0x6076 | `csCZ` |
| 1 | Danish | 0x6064 | `daDK` |
| 3 | German | 0x6066 | `deDE` |
| 4 | Greek | 0x6077 | `elGR` |
| 5 | Spanish | 0x6067 | `esES` |
| 6 | Finnish | 0x6068 | `fiFI` |
| 9 | French | 0x606b | `frFR` |
| 10 | Hungarian | 0x6078 | `huHU` |
| 11 | Italian | 0x606c | `itIT` |
| 12 | Japanese | 0x606d | `jaJP` |
| 13 | Korean | 0x606e | `koKR` |
| 15 | Dutch | 0x6070 | `nlNL` |
| 16 | Norwegian | 0x6071 | `noNO` |
| 17 | Polish | 0x6079 | `plPL` |
| 18 | Portuguese | 0x6072 | `ptPT` |
| 19 | Russian | 0x607a | `ruRU` |
| 20 | Swedish | 0x6073 | `svSE` |
| 21 | Turkish | 0x607b | `trTR` |
| 22 | Chinese (Simplified) | 0x6074 | `zhCN` |
| 23 | Chinese (Traditional) | 0x6075 | `zhTW` |
| 24 | English | 0x6063 | — (main block) |

## Text to translate

| Patch | English text | Where the iPod shows the text |
|---|---|---|
| `dark-mode` | Dark Mode | The name of an item in Settings. The value is On or Off. |
| `album-artists` | Album Artists | An item in the Music menu and in the main menu. Also the title of the screen. Also a row in Settings > Main Menu. |
| `shuffle-album-mix` | Album Mix | A value of Settings > Shuffle, after Off, Songs and Albums. The albums play in a random sequence, and the songs in each album also play in a random sequence. The main menu item "Shuffle: Album Mix" also shows it. The other texts of that item ("Shuffle", Off, Songs, Albums) are Apple strings, and the iPod shows them in its language. |
| `something-comforting` | Something Comforting | The name of an item in Settings. This is the name of a song by Porter Robinson. Do not translate it. |
| `something-comforting` | Play | The value of the item "Something Comforting". A selection of the item plays a part of the song. |
| `usb-audio-out` | USB-C Audio | The name of an item in Settings. Also a row in Settings > Main Menu. The item sends the music to USB-C headphones. |
| `usb-audio-out` | On (44.1 kHz) | A value of the item "USB-C Audio". |
| `usb-audio-out` | On (48 kHz) | A value of the item "USB-C Audio". |
| `usb-audio-out` | USB-C Audio: Off | An item in the main menu. It shows the current value. |
| `usb-audio-out` | USB-C Audio: On | An item in the main menu. It shows the current value. |
| `usb-audio-out` | USB-C Audio: 44.1 kHz | An item in the main menu. It shows the current value. |
| `usb-audio-out` | USB-C Audio: 48 kHz | An item in the main menu. It shows the current value. |

The patch `backlight-60s` has a translation in all languages. It changes the Apple string −140 to "60 Seconds". Use it as an example.

## Translation template

Copy this block. Write your text after each `=`. Leave a line empty if you do not know a good translation.

```
Language:

Dark Mode =
Album Artists =
Album Mix =
Play =
USB-C Audio =
On (44.1 kHz) =
On (48 kHz) =
USB-C Audio: Off =
USB-C Audio: On =
USB-C Audio: 44.1 kHz =
USB-C Audio: 48 kHz =
```

## Apple words on the iPod

This table gives Apple words from firmware 1.3. Use them as a guide for your translation. The number in the heading is the string ID in the firmware.

| Language | Play (−205) | On (24622) | Off (24623) | Albums (−127) | Artists (−126) | Shuffle (−135) | Main Menu (−134) |
|---|---|---|---|---|---|---|---|
| Czech | Přehrát | Zapnuto | Vypnuto | Alba | Umělci | Náhodné pořadí | Hlavní nabídka |
| Danish | Afspil | Til | Fra | Album | Kunstnere | Bland | Hovedmenu |
| German | Wiedergabe | Ein | Aus | Alben | Interpreten | Zufall | Hauptmenü |
| Greek | Εκτέλεση | Ναι | Όχι | Άλμπουμ | Καλλιτέχνες | Τυχαία | Κύριο Μενού |
| Spanish | Reproducir | Sí | No | Álbumes | Artistas | Aleatorio | Menú pral. |
| Finnish | Toista | Päällä | Pois | Albumit | Artistit | Sekoitus | Päävalikko |
| French | Lire | Oui | Non | Albums | Artistes | Aléatoire | Menu principal |
| Hungarian | Játszd le | Be | Ki | Albumok | Előadók | Keverés | Főmenü |
| Italian | Riproduci | Sì | No | Album | Artisti | Casuale | Principale |
| Japanese | 再生 | オン | オフ | アルバム | アーティスト | シャッフル | メインメニュー |
| Korean | 재생 | 켬 | 끔 | 앨범 | 아티스트 | 임의 재생 | 주 메뉴 |
| Dutch | Speel af | Aan | Uit | Albums | Artiesten | Shuffle | Hoofdmenu |
| Norwegian | Spill | På | Av | Albumer | Artister | Miks | Hovedmeny |
| Polish | Graj | Zał | Wył | Albumy | Wykonawcy | Wymieszaj | Menu główne |
| Portuguese | Tocar | Activo | Inactivo | Álbuns | Intérpretes | Aleatório | Menu principal |
| Russian | Воспроизвести | Вкл. | Выкл. | Альбомы | Исполнители | Перемешивание | Главное меню |
| Swedish | Spela | På | Av | Album | Artister | Blanda | Huvudmeny |
| Turkish | Çal | Var | Yok | Albümler | Sanatçılar | Karıştır | Ana Menü |
| Chinese (Simplified) | 播放 | 打开 | 关闭 | 专辑 | 表演者 | 随机播放 | 主菜单 |
| Chinese (Traditional) | 播放 | 開啟 | 關閉 | 專輯 | 演出者 | 隨機播放 | 主選單 |

To see all Apple strings of a language, use the Strings pane of the iPodFirm app. You can also run `ipodfw unpack` and open the files in `work/strings/`.

## Status

"Needed" means that nobody has sent a translation. "Received" means that a translation is in this document, but the patch does not use it yet. "Done" means that the iPod shows the translation.

| Language | `dark-mode` | `album-artists` | `shuffle-album-mix` | `something-comforting` | `usb-audio-out` | `backlight-60s` |
|---|---|---|---|---|---|---|
| Czech | Needed | Needed | Needed | Needed | Needed | Done |
| Danish | Needed | Needed | Needed | Needed | Needed | Done |
| German | Needed | Needed | Needed | Needed | Needed | Done |
| Greek | Needed | Needed | Needed | Needed | Needed | Done |
| Spanish | Needed | Needed | Needed | Needed | Needed | Done |
| Finnish | Needed | Needed | Needed | Needed | Needed | Done |
| French | Needed | Needed | Needed | Needed | Needed | Done |
| Hungarian | Needed | Needed | Needed | Needed | Needed | Done |
| Italian | Needed | Needed | Needed | Needed | Needed | Done |
| Japanese | Needed | Needed | Needed | Needed | Needed | Done |
| Korean | Needed | Needed | Needed | Needed | Needed | Done |
| Dutch | Needed | Needed | Needed | Needed | Needed | Done |
| Norwegian | Needed | Needed | Needed | Needed | Needed | Done |
| Polish | Needed | Needed | Needed | Needed | Needed | Done |
| Portuguese | Needed | Needed | Needed | Needed | Needed | Done |
| Russian | Needed | Needed | Needed | Needed | Needed | Done |
| Swedish | Needed | Needed | Needed | Needed | Needed | Done |
| Turkish | Needed | Needed | Needed | Needed | Needed | Done |
| Chinese (Simplified) | Needed | Needed | Needed | Needed | Needed | Done |
| Chinese (Traditional) | Needed | Needed | Needed | Needed | Needed | Done |

## Received translations

No translations are received yet. Add each new translation here as a copy of the completed template.

## Notes for the maintainer

- The C patches keep each text in one `static const char` array, for example `label[]` in `patches/dark-mode/dark_mode.c`. The patch gives this text for its label ID in all languages.
- To show a translation, the patch calls `0x192ca8`. It returns the language key (0x6063–0x607b). Then the patch selects the text from a table with 25 entries. [re/languages.md](../re/languages.md#the-method-for-a-patch) gives the method and example code.
- Call `0x1d3050(0x6000)` before `0x192ca8`. If the settings object does not exist, `0x192ca8` reads from address 0.
- The method is static research only. Test it in the emulator before you change a patch.
- The patch `backlight-60s` uses the `strings` key of `patch.json`. That key changes Apple strings only. It cannot add a string with a new ID.
- Each translation adds bytes to the patch code. Measure the `size` in `patch.json` again after each change. Increase the `version` of the patch.
- When a patch adds new text, add it to [Text to translate](#text-to-translate), to the template and to the status table.
- The iPodFirm app on the Mac is in English only. It has no string catalog yet. This document does not include the text of the app.
