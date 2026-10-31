# Patch ideas

This file is a list of possible patches for the iPod 5.5G with firmware 1.3. The ideas come from other iPod projects on GitHub. This is research only. Each idea needs work in Ghidra and in the emulator before a patch.

The table "Collisions with the existing patches" shows where an idea can interfere with a patch that we already have.

## Sources

| Project | Device and firmware | What it has | Licence |
|---|---|---|---|
| [lgreitis/osos-lab](https://github.com/lgreitis/osos-lab) (RepriseOS) | iPod Classic, 2.0.5 | Custom EQ, Play Next and Play Last, Song Info, Album Artists, Dark Mode, the EU volume limit, a CFW information screen, a crash screen | GPL-3.0. Use the ideas and the notes. Do not copy the code. |
| [bydash-xyz/ipod-cjk-patch](https://github.com/bydash-xyz/ipod-cjk-patch) | iPod Video, 1.3 | Clean Chinese, Japanese and Korean fonts in the lists and in the lyrics | Not checked. The lyric fonts come from Fusion Pixel (OFL). |
| [slushiimusic/ipod-classic-usbc-charging-indicator](https://github.com/slushiimusic/ipod-classic-usbc-charging-indicator) | iPod Video 5G, 1.3 | A charge icon for USB-C kits that charge the battery directly | Not checked |
| [dantidote/ipod-wav-fix](https://github.com/dantidote/ipod-wav-fix) | iPod 1G, 1.5 | An earlier refill of the audio cache for WAV and AIFF | Not checked |
| [davidbarnhart/flashpod](https://github.com/davidbarnhart/flashpod) | iPod 1G, 1.5 | FLAC playback, an earlier refill, LBA48, a fix for a memory leak | MIT. The FLAC code comes from "openpod". That repository is not public. |

## Ideas

| # | Idea | Source | Value | Work | First research step |
|---|---|---|---|---|---|
| 1 | Play Next and Play Last | osos-lab `play_next.c` | High | Medium to high | Done: refer to [play-next.md](play-next.md). Play Last can use the add method of the play list. Play Next must also move the songs. |
| 2 | Song Info | osos-lab `song_info.c` | High | Medium | Paused (21 October 2026): refer to [song-info.md](song-info.md). The track object has most fields. A patch cannot point a menu item at a new screen; a possible design uses the Main Menu screen with other texts. |
| 3 | USB-C charge icon | slushiimusic | Low for our mod | Low to medium | Probably not necessary. Refer to the item below. |
| 4 | Patch list in Settings > About | osos-lab `cfw_info` | Medium | Low | Find the About screen and how it gets its rows. |
| 5 | Custom EQ | osos-lab `custom_eq.c` | High | High | Done: the patch `custom-eq`. Refer to [custom-eq.md](custom-eq.md). |
| 6 | CJK fonts | ipod-cjk-patch | High for CJK users | Medium | Measure the free space in rsrc after the dark theme. |
| 7 | Early cache refill | ipod-wav-fix, flashpod `flac-refill` | Medium | Medium | Play a long WAV or ALAC song without `flash-keep-awake`. Listen for a pause at the refill. |
| 8 | Crash screen | osos-lab `panic.c` | For development | Medium | Find the crash handler of 1.3. |
| 9 | Custom boot logo | Rockbox boot logo patcher, iPodWizard | Low | Low | Find the Apple logo picture in rsrc. |
| 10 | FLAC playback (for later) | flashpod | High | Very high | Find the decoder table of 1.3. |
| 11 | Music from USB-C and the headphone jack at the same time | The owner | Medium | High | Saved for later: refer to [usb-dual-out.md](usb-dual-out.md). Read 0x1a2d60 and the codec driver in Ghidra. |
| 12 | More tracks on a 32 MB iPod | Rockbox, the owner | High for owners of a 32 MB iPod | Low to high | Done: refer to [ram-limit.md](ram-limit.md). The Rockbox method is not practical in RetailOS. A 32 MB iPod already shares equal strings. The next step is to find the size of the music buffer. |

### 1. Play Next and Play Last

The owner holds Select on a song, an album or an artist. A menu shows Play Next and Play Last. Play Next puts the item after the current song. Play Last puts the item at the end of the current list. Firmware 1.3 only adds the item to On-The-Go, which is a different playlist.

osos-lab copies the database entry into the playback list. If shuffle is on, it moves the shuffle rank of each later song by one. It stops the artwork task during the change. Then it clears the next song that the player prepared.

### 2. Song Info

A screen shows the data of a song: title, artist, album, Album Artist, composer, genre, year, file format, bit rate, sample rate, file size, duration, play count, skip count, rating, date added, last played and the file path. Most fields are in iTunesDB. The patch only reads data, so the risk is low.

### 3. USB-C charge icon

Some USB-C kits charge the battery through their own board. The iPod then does not know that it charges. The slushiimusic patch reads the battery voltage each 250 ms and shows the charge icon after a fast increase. The icon is an estimate, and the patch cannot see a charger when the iPod sleeps.

In [../docs/usb-c-power-mod.md](../docs/usb-c-power-mod.md), the iPod charges through its normal input. Thus this patch is probably not necessary for our mod.

### 5. Custom EQ

Firmware 1.3 has only fixed EQ presets. osos-lab adds a preset with three bands. Each band has a filter type, a frequency, a gain and a Q. A precut lowers the full volume to prevent clipping. The settings stay in a file on the iPod.

The research found that 1.3 uses a software EQ. Each preset is a chain of up to 5 biquads from a fixed table (refer to [custom-eq.md](custom-eq.md)). The patch `custom-eq` adds 5 free biquads to this table. The app calculates them and adds a precut.

### 7. Early cache refill

The iPod reads a large part of the song into RAM and stops the disk. When the RAM is almost empty, it starts the disk again. WAV, AIFF and ALAC files are large, so the refills occur more frequently. If the disk start takes longer than the audio in the cache, the music stops for a short time.

A flash adapter needs 3–6 s to start after a power cut (refer to [play-latency.md](play-latency.md)). The patch `flash-keep-awake` probably hides the problem.

### 10. FLAC playback (for later)

The flashpod FLAC fix for the iPod 1G has these parts:

- A decoder of 363,916 bytes after the end of the firmware.
- A new entry `"fla"` in the table that connects a file type to a decoder.
- The fix `flac-refill`, which refills the cache earlier for long files.
- FLAC songs in iTunesDB with their own file-type marker. Without this, the iPod cannot see the songs.

The bytes are for a different firmware, so we cannot use them. A FLAC patch for the iPod Video needs these steps:

1. Find the decoder table and the interface of the ALAC decoder in 1.3.
2. Port a small decoder with a free licence, for example `dr_flac` (public domain) or libFLAC (BSD).
3. Support 16-bit files first. The iPod output is 16-bit, 44.1 kHz. Other files need a conversion on the iPod.
4. Add the seek for fast forward and rewind.
5. Add FLAC to `MusicImport.swift`. It now accepts only `.m4a` and `.mp4`. Read the Vorbis comments and the cover picture.

An easier alternative: the iPodFirm app converts each FLAC file to ALAC at import. ALAC is also lossless, and 1.3 already plays it. This needs no change to the firmware.

## Ideas from the review of 31 October 2026

The ideas in this section have no firmware research, except where a line gives a note. The fit and the work values are estimates.

### New ideas

| Idea | Value | Work | Note |
|---|---|---|---|
| Split home screen | High | Medium, not tested | A mod of 2007 did this on the 5.5G. The list uses the left 2/3. The right 1/3 shows the cover, the song, the album and the artist. A mini player below the list is the fallback. Refer to [home-screen.md](home-screen.md). |
| Battery display options | Medium | Low to medium | Icon, Icon + Percent, Percent. Research: [battery.md](battery.md). The firmware has a hidden number display. |
| Numeric volume | Medium | Low | The firmware has the switch `_show_numeric_volume`. Refer to [device-switches.md](device-switches.md). |
| Main menu order | High | Low | The app reorders the items of Menu 24094. Check the effect on the mask at 0x105a04. PodBox also has this. |
| Compact lists | Medium | Low | Shows more rows. The width test of the split home screen also tells if this is possible. |
| Large cover in Now Playing | High | Medium | A key shows the 200 × 200 cover on a full screen. |
| Scrobble log | High | Medium | Records the time of each play for Last.fm. `playback-log` has most of the hooks. |
| On-device statistics | Medium | Medium | Most played songs, from the track object. |

### Ideas from Rockbox and from custom Rockbox builds

PodBox and Rockpod use GPL-2.0. Use only the ideas. Do not copy their code.

| Idea | Source | Value | Fit to RetailOS | Work | First research step |
|---|---|---|---|---|---|
| Art in the Artists list | PodBox | High | Good. `album-art` has the row hook. | Medium | Select a cover for each artist. |
| Theme colours from the cover | Rockpod, PodBox | High | Partly. Views copy the colours at the start, thus a live change must write to each view. | High | Find if a change of the highlight colour in a live view has an effect. |
| Forgotten albums, Recently Played, Most Played | PodBox | High | Good. The track object has the play count and the last-played date. | Medium | Find how to fill a list with a new order. |
| Listening report | PodBox | High | Good, in the app. The iPod records. The app shows the year summary. | Medium | Use the scrobble log as the data. |
| Sleep timer from Now Playing | PodBox, Rockbox | Medium | Good. `sleep-now` has the sleep call. | Low to medium | Find a free key action in Now Playing. |
| Sort of albums by year or by artist | PodBox | Medium | Not known. The firmware keeps sort indexes. | Medium | Read the sort indexes in [firmware-library.md](firmware-library.md). |
| Remove "feat." and the remaster text from titles | PodBox | Medium | Good. The app can do this at sync, or a label hook can do it. | Low | Decide: app or firmware. |
| Random Album item | PodBox | Medium | Good. It can reuse `shuffle-album-mix`. | Low to medium | Add a main menu action item. |
| Audiobook: mark as finished | PodBox | Low | Probably good. | Medium | Find the bookmark field. |
| Crossfade | Rockbox | High | Poor. It needs two decoders at the same time. | Very high | Find if the decoder task can run two times. |
| Crossfeed, stereo width | Rockbox | Medium | Not known. `custom-eq` filters each channel, but these need a mix of the 2 channels. | High | Read [custom-eq.md](custom-eq.md). |
| Dynamic range compressor | Rockbox | Medium | Not known. It adds CPU load in the audio path. | High | Find a hook in the audio path. |
| Variable speed with the same pitch | Rockbox | Medium | Poor. It needs much CPU. | Very high | Measure the free CPU first. |
| Faster wake with flash storage | Rockpod | Medium | Rockpod does this only on the Classic. `flash-keep-awake` and `flash-wake-on-input` already do part of this. | Medium | Measure the wake time. |
| Do not count a weak USB source as a charger | Rockpod | Low | Rockpod does this only on the Classic. It can apply to USB-C mods. | Medium | Read [firmware-power.md](firmware-power.md). |
| Cover Flow song menu | RepriseOS wishlist | Medium | Not known. | Medium | Read the `up-next` hold code. |
| Apple debug menu, with a disk log | RepriseOS wishlist | For development | Not known. | Medium | Find the debug menu in 1.3. |
| Fonts and resources from files | RepriseOS wishlist | Medium | Not known. It can help the CJK fonts. | High | Find the font load path. |

Not useful for this project: Bluetooth (no source found), 192 kHz audio (the output is 44.1 kHz, 16 bits), Music Quiz, games, and the image and text viewers. `search-5g` already gives the Search screen.

Limits of the search: the Rockbox plugin index, the Foxbox page and one Reddit copy did not open. The Rockbox facts come from copies of the manual, not from the current manual.

Sources: [PodBox](https://github.com/anthonyfletcher/podbox), [Rockpod](https://github.com/nuxcodes/rockpod), [osos-lab](https://github.com/lgreitis/osos-lab), [osos-lab wishlist](https://raw.githubusercontent.com/lgreitis/osos-lab/main/PATCH-WISHLIST.md), [Rockbox playback options](https://repo.or.cz/Rockbox.git/blob/HEAD:/manual/configure_rockbox/playback_options.tex), [Rockbox sound settings](https://git.lenord.me/devs/foxbox/raw/commit/2306433eb70628d2f9c042ced7ea0d2912e31cc9/manual/configure_rockbox/sound_settings.tex), [Rockbox 4.0 report](https://www.howtogeek.com/rockbox-4-0-custom-firmware-mp3-players-old-ipods/).

## Collisions with the existing patches

Hook chains let two patches change the same hook word (refer to [../docs/patch-system.md](../docs/patch-system.md), "Hook chains"). Thus most collisions are in the behaviour, not in the hooks.

| Idea | Collides with | Problem | Possible solution |
|---|---|---|---|
| Play Next | `cover-flow` | A hold of Select in the Albums list opens Cover Flow (event type 6). In the other lists, the hold adds the item to On-The-Go. | The hold opens a small menu: Play Next, Play Last, Add to On-The-Go, and Cover Flow (only in Albums). The owner decides. |
| Play Next | `shuffle-fixes`, `shuffle-album-mix` | Play Next must move the shuffle ranks. `shuffle-fixes` changes the shuffle for more than 32767 songs. Album Mix shuffles in each album (`+0x93`). | Use [shuffle-model.py](shuffle-model.py). Test with Songs, Albums and Album Mix. |
| Play Next | `album-art`, `cover-flow` | osos-lab stops the artwork task during the change, because the artwork uses the queue position. | Find if the artwork task of 1.3 (0x205db4) uses a queue position. |
| Play Next | `album-artists` | The Album Artists lists also need Play Next. | This is extra work, not a conflict. |
| Song Info | `cover-flow`, On-The-Go | The hold of Select is already in use. | Open Song Info from Now Playing, or from the small menu of Play Next. |
| Song Info | `dark-mode` | A new screen must use the colours of the theme. | Use the native list screen. |
| Custom EQ | `usb-audio-out` | The USB output takes the decoder buffers before the codec (0x1a2d60). The EQ of 1.3 is a software EQ, so it probably also changes the USB-C audio. | Test on the real iPod: play with an EQ preset through USB-C. |
| Custom EQ | `volume-unlimit` | A boost with no volume limit causes clipping. | The app adds a precut. |
| Early refill | `flash-keep-awake`, `flash-wake-on-input` | These patches hook the storage power (0x284c7c, 0x23344c, 0x1d8344). Keep-awake probably hides the pause. | Test without keep-awake first. Use a different hook word or a chain. |
| Early refill, FLAC | `usb-audio-out` | The USB music buffers (52 KB) also use RAM. A larger cache needs more RAM. | Measure the free RAM. |
| USB-C charge icon | the branches `usb-vbus-test` and `battery-research` | If the iPod supplies power to USB-C headphones, the battery voltage decreases. A detector that uses the voltage then gives wrong results. | Probably do not make this patch. |
| CJK fonts | `dark-mode` (the moved rsrc) | Larger fonts in rsrc need space. The dark theme already moves rsrc. | Measure the free space after the dark theme. |
| Boot logo | `dark-mode` | The dark theme can change pictures in rsrc. | Find if the theme changes the Apple logo. |
| FLAC | all extended patches, `dark-mode` | All use the area up to 0x7F8000 (`ThemeImport.ososLimit`). | Measure the free space with all patches. |
| Patch list in About, crash screen | None found | — | — |
| Split home screen | `dark-mode`, `album-art`, `cover-flow` | The theme can change the same View bytes. The panel needs the theme colours. The cover load can stop the wheel. | Check the View bytes. Use the firmware artwork task. |
| Battery display options | `dark-mode` | The text style must have a correct colour in the two themes. | Test the two themes. |

## Not recommended

- Doom and games from osos-lab. They are not complete.
- The 128 GB fix for the iPod Classic 6G ([thisiiso/ipod-classic-6g-firwmare-mod](https://github.com/thisiiso/ipod-classic-6g-firwmare-mod)). It is for a different SoC. It replaces the firmware through a SysCfg change and does not patch the code. The iPod Video with 1.3 operates with large cards, but we have not checked its disk driver in Ghidra.
