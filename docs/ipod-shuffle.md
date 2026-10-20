# The iPod shuffle: a specification and code to copy it

This document tells how the iPod Video 5.5G (firmware 1.3) makes its shuffled play order. It also gives code in C and in Swift. The code makes the same order as the iPod from the same seed. Add the code to a music player or to an iTunes replacement to get the "iPod shuffle" behaviour.

The facts come from a disassembly of the firmware (Ghidra) and from tests of the unchanged firmware in an emulator. Each code example in this document passes the tests in [Test values](#7-test-values).

## Contents

1. [What the user sees](#1-what-the-user-sees)
2. [The random number generator](#2-the-random-number-generator)
3. [The shuffle algorithm](#3-the-shuffle-algorithm)
4. [How to add it to a player](#4-how-to-add-it-to-a-player)
5. [C and C++ code](#5-c-and-c-code)
6. [Swift code](#6-swift-code)
7. [Test values](#7-test-values)
8. [Bugs in the firmware](#8-bugs-in-the-firmware)
9. [Limits of this document](#9-limits-of-this-document)

## 1. What the user sees

The iPod has one shuffle setting, Settings → Shuffle. It has three values: Off, Songs and Albums. Each push of the centre button on the item goes to the next value: Off → Songs → Albums → Off.

| Setting | Result |
|---|---|
| Off | The songs play in the sequence of the list. |
| Songs | All the songs of the list play in a random sequence. Each song plays one time. |
| Albums | The albums of the list play in a random sequence. The songs of each album play in their album sequence. |

The shuffle occurs at these times:

- The user selects **Shuffle Songs** in the main menu. The iPod shuffles all the songs of the library. There is no current song, so the first song of the result plays first.
- The user selects a song in a list while Shuffle is not Off. The iPod shuffles that list. The selected song plays first.
- A smart playlist has a limit "selected by random". The iPod uses the same shuffle to select the songs. The Shuffle setting (Songs or Albums) also applies here.

The iPod does not use this shuffle for "Shuffle Photos" in a slideshow. The slideshow uses a different, simpler method.

## 2. The random number generator

### 2.1 The generator

The generator is the Park–Miller "minimal standard" generator. The state is a signed 32-bit integer. The iPod uses the Schrage form, without 64-bit multiplication:

```text
state = 16807 × (state mod 127773) − 2836 × (state div 127773)
if state < 1 then state = state + 2147483647
```

`div` and `mod` are signed integer division and remainder that truncate toward zero, as in C. 127773 = 2147483647 div 16807, and 2836 = 2147483647 mod 16807.

### 2.2 The random index

The shuffle needs an index from 0 to n − 1. The iPod makes it with single-precision (32-bit) floats:

```text
u     = float32(state) × 2^−31
p     = float32(n) × u
index = truncate(p)        (toward zero)
```

Each operation rounds to the nearest float32 value, with ties to even. You must use float32 and this sequence of operations. If you use double precision or a different formula, some indexes change and the order is not the same as on the iPod.

The iPod first calculates the next state, then the index. Thus each call uses one new state.

### 2.3 The seed

- The iPod sets the seed one time after each start of the iPod. It does this at the first shuffle.
- The seed is `A XOR (B << 16)`. A and B are two reads of a fast 16-bit hardware counter. Thus the seed is different at each start.
- The state stays in memory until the iPod stops. All shuffles after one start use one continuous sequence of random numbers.

Do the same in your player: make one generator when the program starts, and keep it. Do not make a new generator for each shuffle.

Three seeds stop the generator: 0, 0x7fffffff and 0x80000001. With these seeds the state becomes 0x7fffffff and does not change again. Do not use them. Refer to [Bug 2](#bug-2-seeds-that-stop-the-generator).

## 3. The shuffle algorithm

### 3.1 The basic shuffle

Both modes use the same Fisher–Yates shuffle. The loop goes from the end of the array to the start:

```text
i = n
while i > 1:
    j = index(i)              ; 0 … i − 1
    swap a[j] and a[i − 1]
    i = i − 1
```

A shuffle of n items uses n − 1 random indexes.

### 3.2 Songs mode

1. Take the songs of the list in the sequence of the list. For Shuffle Songs, this is the sequence of the iPod database (the sequence of the sync), not the title sequence of the Songs menu.
2. Shuffle all the songs with the basic shuffle. The current song is also in the shuffle.
3. If there is a current song, move it to position 0. Each song that was before it moves one position later. The songs after it do not move.

### 3.3 Albums mode

1. Take the songs of the list in **album order**. The iPod uses the album index of its database. A sync program writes this index (iTunesDB mhod 52, sort type 4: album, then disc, then track number). If the index is not there, the iPod sorts the list itself.
2. Divide the sorted list into groups. A group is a run of songs that have the same album name as the first song of the group.
   - The compare is exact and case-sensitive. "Abbey Road" and "abbey road" are two groups.
   - The iPod compares only the first 255 UTF-16 code units of a name.
   - A song with an empty album name is always a group of its own.
3. Shuffle the groups with the basic shuffle. n is the number of groups.
4. If there is a current song, swap its group with the group at position 0. This is a swap, not a move: the old first group goes to the old place of the current group.
5. Write the songs of each group in the new group sequence. The songs in a group keep their sequence.

The current song does not move to position 0 in Albums mode. It stays at its place in its album. Thus the songs of its album before it are before it in the play order. The iPod starts playback at the current song, and Now Playing shows its real position, for example "3 of 60".

### 3.4 After the shuffle

The player plays the result from the position of the current song (position 0 if there is no current song). If the user sets Shuffle to Off, the original list sequence comes back, and the current song continues.

## 4. How to add it to a player

1. Make one generator when the program starts. Give it a seed from two random 16-bit values. Do not use a seed that stops the generator.
2. Keep the shuffle mode (Off, Songs, Albums) as a user setting.
3. When the user starts a list, call the play order function with the list, the mode and the index of the selected song.
4. Start playback at the returned position.
5. When the user changes the mode, call the function again with the index of the current song. Continue at the returned position.
6. For Albums mode, give an album sort that is the same as the album sort of your library. The code sorts by album name, disc number and track number.

To get the iPod order for a given iPod list, give the songs in the sequence of the iPod database and the seed of that start of the iPod. Normally the seed is not known, so the aim is the same behaviour, not the same order.

## 5. C and C++ code

The code is one header file. It compiles as C99 and as C++ (tested with clang, `-std=c99` and `-std=c++17`, with `-Wall -Wextra -Werror`).

CAUTION: The compiler must calculate `float` values in single precision (`FLT_EVAL_METHOD` = 0). This is correct for ARM and for x86-64 with SSE. On old 32-bit x86 with the x87 unit, use `-msse2 -mfpmath=sse`. If you do not, some indexes are different from the iPod.

### 5.1 `ipod_shuffle.h`

```c
/* ipod_shuffle.h - a copy of the iPod 5.5G music shuffle (RetailOS 1.3).
 * Compiles as C99 and as C++. Use a compiler with FLT_EVAL_METHOD == 0
 * (all ARM and x86-64 compilers with SSE). */
#ifndef IPOD_SHUFFLE_H
#define IPOD_SHUFFLE_H

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define IPOD_MODULUS 0x7fffffff

typedef struct {
    int32_t state;
} ipod_rng;

/* Set the seed. The firmware uses the seed as is. */
static inline void ipod_rng_seed(ipod_rng *r, uint32_t seed)
{
    r->state = (int32_t)seed;
}

/* The firmware seed: two 16-bit samples A and B of a fast counter. */
static inline uint32_t ipod_make_seed(uint16_t a, uint16_t b)
{
    return (uint32_t)a ^ ((uint32_t)b << 16);
}

/* 1 if the seed stops the generator (the state stays at 0x7fffffff). */
static inline int ipod_seed_locks(uint32_t seed)
{
    return (int64_t)(int32_t)seed % IPOD_MODULUS == 0;
}

/* Park-Miller "minimal standard", Schrage form. C division truncates
 * toward zero, as the firmware division does. */
static inline int32_t ipod_rng_next(ipod_rng *r)
{
    int64_t s = r->state;
    int64_t v = 16807 * (s % 127773) - 2836 * (s / 127773);
    if (v < 1)
        v += IPOD_MODULUS;
    r->state = (int32_t)v;
    return r->state;
}

/* A random index in 0 ... n-1, in single precision as the firmware does.
 * The firmware returns n for the states 0x7fffffc0 ... 0x7ffffffe.
 * This copy returns n - 1 for these states. */
static inline int ipod_rng_index(ipod_rng *r, int n)
{
    float u = (float)ipod_rng_next(r) * 0x1p-31f;
    float p = (float)n * u;
    int i = (int)p;
    return i < n ? i : n - 1;
}

/* Fisher-Yates from the end of the array to the start. */
static inline void ipod_shuffle_ints(int *a, int n, ipod_rng *r)
{
    int i, j, t;
    for (i = n; i > 1; i--) {
        j = ipod_rng_index(r, i);
        t = a[j];
        a[j] = a[i - 1];
        a[i - 1] = t;
    }
}

/* Songs mode. Writes a permutation of 0 ... n-1 to order.
 * current is a position in the list, or -1 for no current song. */
static inline void ipod_shuffle_songs(int *order, int n, int current, ipod_rng *r)
{
    int i, at = -1;
    for (i = 0; i < n; i++)
        order[i] = i;
    ipod_shuffle_ints(order, n, r);
    for (i = 0; i < n; i++)
        if (order[i] == current)
            at = i;
    if (at > 0) {
        memmove(order + 1, order, (size_t)at * sizeof(int));
        order[0] = current;
    }
}

/* Albums mode. album[i] is the album name (UTF-8) at position i of a list
 * that is in album order. Writes a permutation of 0 ... n-1 to order.
 * current is a position in the list, or -1. Returns 0, or -1 if there
 * is no memory. The firmware compares only the first 255 UTF-16 units
 * of a name. */
static inline int ipod_shuffle_albums(int *order, const char *const *album, int n,
                               int current, ipod_rng *r)
{
    int *start = (int *)malloc((size_t)(n + 1) * sizeof(int));
    int *group = (int *)malloc((size_t)(n + 1) * sizeof(int));
    int count = 0, i, k, out = 0, first = 0;
    if (start == NULL || group == NULL) {
        free(start);
        free(group);
        return -1;
    }
    /* A group is a run of songs with the same name as its first song.
     * A song with an empty name is a group of its own. */
    for (i = 0; i < n; i++) {
        if (i == 0 || album[i][0] == '\0' ||
            strcmp(album[i], album[start[count - 1]]) != 0)
            start[count++] = i;
    }
    start[count] = n;
    for (k = 0; k < count; k++)
        group[k] = k;
    ipod_shuffle_ints(group, count, r);
    /* Swap the group of the current song with the first group. */
    if (current >= 0) {
        for (k = 0; k < count; k++) {
            int g = group[k];
            if (current >= start[g] && current < start[g + 1]) {
                first = group[0];
                group[0] = g;
                group[k] = first;
                break;
            }
        }
    }
    for (k = 0; k < count; k++)
        for (i = start[group[k]]; i < start[group[k] + 1]; i++)
            order[out++] = i;
    free(start);
    free(group);
    return 0;
}

/* ---- The entry point for a music player ---------------------------- */

typedef enum { IPOD_SHUFFLE_OFF, IPOD_SHUFFLE_SONGS, IPOD_SHUFFLE_ALBUMS } ipod_shuffle_mode;

/* The data that the shuffle needs from each track of your list. */
typedef struct {
    const char *album; /* UTF-8, "" if the track has no album */
    int disc;          /* 0 if not known */
    int number;        /* track number, 0 if not known */
} ipod_track;

static const ipod_track *ipod_sort_tracks; /* qsort has no context argument */

static inline int ipod_album_compare(const void *pa, const void *pb)
{
    int a = *(const int *)pa, b = *(const int *)pb, c;
    const ipod_track *x = &ipod_sort_tracks[a], *y = &ipod_sort_tracks[b];
    c = strcmp(x->album, y->album);
    if (c != 0)
        return c;
    if (x->disc != y->disc)
        return x->disc < y->disc ? -1 : 1;
    if (x->number != y->number)
        return x->number < y->number ? -1 : 1;
    return a < b ? -1 : a > b; /* keep the list order for equal tracks */
}

/* Write the play order of tracks[0 ... n-1] to order: order[k] is the
 * index of the track that plays at position k. current is the index of the
 * track that plays now (or the track that the user selected), or -1.
 * Returns the position of current in order (0 if current is -1), or -1 if
 * there is no memory. The function is not thread-safe (qsort context). */
static inline int ipod_play_order(int *order, const ipod_track *tracks, int n,
                                  ipod_shuffle_mode mode, int current, ipod_rng *r)
{
    int i, pos = 0;
    if (mode == IPOD_SHUFFLE_OFF) {
        for (i = 0; i < n; i++)
            order[i] = i;
        return current > 0 ? current : 0;
    }
    if (mode == IPOD_SHUFFLE_SONGS) {
        ipod_shuffle_songs(order, n, current, r);
        return 0;
    }
    {
        /* Albums: the iPod groups the albums in an album-sorted list. */
        int *byalbum = (int *)malloc((size_t)(n + 1) * sizeof(int));
        int *shuffled = (int *)malloc((size_t)(n + 1) * sizeof(int));
        const char **names = (const char **)malloc((size_t)(n + 1) * sizeof(char *));
        int cur = -1;
        if (byalbum == NULL || shuffled == NULL || names == NULL) {
            free(byalbum);
            free(shuffled);
            free((void *)names);
            return -1;
        }
        for (i = 0; i < n; i++)
            byalbum[i] = i;
        ipod_sort_tracks = tracks;
        qsort(byalbum, (size_t)n, sizeof(int), ipod_album_compare);
        for (i = 0; i < n; i++) {
            names[i] = tracks[byalbum[i]].album;
            if (byalbum[i] == current)
                cur = i;
        }
        if (ipod_shuffle_albums(shuffled, names, n, cur, r) != 0)
            pos = -1;
        else
            for (i = 0; i < n; i++) {
                order[i] = byalbum[shuffled[i]];
                if (order[i] == current)
                    pos = i;
            }
        free(byalbum);
        free(shuffled);
        free((void *)names);
        return pos;
    }
}

#endif
```

The functions:

| Function | Use |
|---|---|
| `ipod_rng_seed`, `ipod_make_seed`, `ipod_seed_locks` | Set the seed. |
| `ipod_rng_next`, `ipod_rng_index` | The generator and the random index. |
| `ipod_shuffle_songs`, `ipod_shuffle_albums` | The two modes, on positions of a list. `ipod_shuffle_albums` needs a list in album order. |
| `ipod_play_order` | The entry point for a player: it sorts for Albums mode and returns the position of the current track. |

`ipod_play_order` uses `qsort` with a static variable, thus it is not thread-safe. Call it from one thread, or protect it with a lock. The album sort uses `strcmp`. Replace `ipod_album_compare` if your library sorts albums in a different way, for example without case.

### 5.2 Example

```c
#include <stdio.h>
#include <time.h>
#include "ipod_shuffle.h"

/* One generator for the life of the program, as on the iPod. */
static ipod_rng shuffle_rng;

/* Call one time when the program starts. */
static void shuffle_init(void)
{
    uint32_t seed;
    do {
        seed = ipod_make_seed((uint16_t)rand(), (uint16_t)clock());
        srand(seed + 1);
    } while (ipod_seed_locks(seed));
    ipod_rng_seed(&shuffle_rng, seed);
}

int main(void)
{
    /* The list that the user plays, in the sequence of the list. */
    static const ipod_track tracks[6] = {
        {"Alpha", 1, 1}, {"Beta", 1, 1}, {"Alpha", 1, 2},
        {"Beta", 1, 2}, {"Gamma", 1, 1}, {"Alpha", 1, 3},
    };
    int order[6], pos, k;

    srand((unsigned)time(NULL));
    shuffle_init();

    /* The user selects track 3 ("Beta" 2) with Shuffle = Albums. */
    pos = ipod_play_order(order, tracks, 6, IPOD_SHUFFLE_ALBUMS, 3, &shuffle_rng);
    if (pos < 0)
        return 1;
    for (k = pos; k < 6; k++) /* play from the current track */
        printf("%s %d\n", tracks[order[k]].album, tracks[order[k]].number);
    return 0;
}
```

The output starts with `Beta 2`. The album "Beta" is the first group, and the selected song is its second song.

## 6. Swift code

The code is one file with no imports. It needs Swift 5.9 or later.

### 6.1 `IPodShuffle.swift`

```swift
// IPodShuffle.swift - a copy of the iPod 5.5G music shuffle (RetailOS 1.3).

/// The random numbers: Park-Miller "minimal standard" in Schrage form, and
/// an index in single precision, as the firmware makes it.
public struct IPodRandom: Sendable, Equatable {
    public static let modulus: Int32 = 0x7FFF_FFFF
    public private(set) var state: Int32

    /// The firmware uses the seed as is.
    public init(seed: UInt32) {
        state = Int32(bitPattern: seed)
    }

    /// The firmware seed: two 16-bit samples A and B of a fast counter.
    public static func seed(a: UInt16, b: UInt16) -> UInt32 {
        UInt32(a) ^ (UInt32(b) << 16)
    }

    /// A random seed that does not stop the generator.
    public static func randomSeed() -> UInt32 {
        while true {
            let seed = seed(a: .random(in: .min ... .max), b: .random(in: .min ... .max))
            if !locksUp(seed) { return seed }
        }
    }

    /// True if the seed stops the generator (the state stays at 0x7fffffff).
    public static func locksUp(_ seed: UInt32) -> Bool {
        Int64(Int32(bitPattern: seed)) % Int64(modulus) == 0
    }

    /// The next state. Swift `/` and `%` truncate toward zero, as the
    /// firmware division does.
    @discardableResult
    public mutating func next() -> Int32 {
        let s = Int64(state)
        var v = 16807 * (s % 127_773) - 2836 * (s / 127_773)
        if v < 1 { v += Int64(Self.modulus) }
        state = Int32(truncatingIfNeeded: v)
        return state
    }

    /// A value in 0..<n. The firmware returns n for the states
    /// 0x7fffffc0...0x7ffffffe. This copy returns n - 1 for these states.
    public mutating func index(below n: Int) -> Int {
        precondition(n > 0)
        let u = Float(next()) * 0x1p-31
        let p = Float(n) * u
        return min(Int(p), n - 1)
    }
}

public enum IPodShuffle {
    /// Fisher-Yates from the end of the array to the start.
    static func shuffle<T>(_ items: inout [T], using random: inout IPodRandom) {
        var i = items.count
        while i > 1 {
            items.swapAt(random.index(below: i), i - 1)
            i -= 1
        }
    }

    /// Songs mode. Returns a permutation of 0..<count. The current song
    /// goes to the start. The songs before it move one position later.
    public static func songs(count: Int, current: Int?, using random: inout IPodRandom) -> [Int] {
        var order = Array(0..<count)
        shuffle(&order, using: &random)
        if let current, let at = order.firstIndex(of: current) {
            order.remove(at: at)
            order.insert(current, at: 0)
        }
        return order
    }

    /// Albums mode. `albums` is the album name at each position of a list
    /// in album order. Returns a permutation of the positions. The group of
    /// the current song changes places with the first group.
    public static func albums(_ albums: [String], current: Int?, using random: inout IPodRandom) -> [Int] {
        var groups: [[Int]] = []
        var groupName: [UInt16] = []
        for (position, album) in albums.enumerated() {
            let name = Array(album.utf16.prefix(255))
            if !name.isEmpty, !groups.isEmpty, name == groupName {
                groups[groups.count - 1].append(position)
            } else {
                groups.append([position])
                groupName = name
            }
        }
        shuffle(&groups, using: &random)
        if let current, let at = groups.firstIndex(where: { $0.contains(current) }) {
            groups.swapAt(0, at)
        }
        return groups.flatMap { $0 }
    }
}

// MARK: - The entry point for a music player

extension IPodShuffle {
    /// Settings > Shuffle on the iPod.
    public enum Mode: String, CaseIterable, Sendable {
        case off, songs, albums

        /// The sequence of the iPod Settings item: Off, Songs, Albums.
        public var next: Mode {
            switch self {
            case .off: .songs
            case .songs: .albums
            case .albums: .off
            }
        }
    }

    /// The play order of `tracks`: `order[k]` is the index of the track that
    /// plays at position k. `current` is the index of the track that plays
    /// now, or the track that the user selected. `position` is where
    /// `current` is in `order`.
    ///
    /// - `album` gives the album name of a track.
    /// - `albumOrder` sorts two tracks of a list in album order (for example
    ///   album name, then disc, then track number). Albums mode uses it.
    public static func playOrder<Track>(
        for tracks: [Track],
        mode: Mode,
        current: Int?,
        album: (Track) -> String,
        albumOrder: (Track, Track) -> Bool,
        using random: inout IPodRandom
    ) -> (order: [Int], position: Int) {
        let order: [Int]
        switch mode {
        case .off:
            order = Array(tracks.indices)
        case .songs:
            order = songs(count: tracks.count, current: current, using: &random)
        case .albums:
            // The iPod groups the albums in an album-sorted list.
            let byAlbum = tracks.indices.sorted { a, b in
                if albumOrder(tracks[a], tracks[b]) { return true }
                if albumOrder(tracks[b], tracks[a]) { return false }
                return a < b
            }
            order = albums(byAlbum.map { album(tracks[$0]) },
                           current: current.flatMap { byAlbum.firstIndex(of: $0) },
                           using: &random)
                .map { byAlbum[$0] }
        }
        return (order, current.flatMap { order.firstIndex(of: $0) } ?? 0)
    }
}
```

Swift `Float` uses IEEE single precision with round to nearest, ties to even, on all platforms. Thus the index is the same as on the iPod.

### 6.2 Example: a play queue

This example uses Foundation for `localizedStandardCompare`.

```swift
import Foundation
struct Song {
    var title: String
    var album: String
    var disc = 1
    var track = 0
}

/// A small player queue. One generator for the life of the program, as on
/// the iPod: it gets its seed one time.
final class Queue {
    private(set) var songs: [Song] = []
    private(set) var order: [Int] = []
    private(set) var position = 0
    private(set) var mode = IPodShuffle.Mode.off
    private var random: IPodRandom

    init(random: IPodRandom = IPodRandom(seed: IPodRandom.randomSeed())) {
        self.random = random
    }

    var current: Song? { order.indices.contains(position) ? songs[order[position]] : nil }

    /// The user selects a song in a list.
    func play(_ list: [Song], startingAt index: Int) {
        songs = list
        reorder(current: index)
    }

    /// The user changes Settings > Shuffle. The current song continues.
    func setMode(_ newMode: IPodShuffle.Mode) {
        mode = newMode
        reorder(current: order.isEmpty ? nil : order[position])
    }

    func next() -> Song? {
        guard position + 1 < order.count else { return nil }
        position += 1
        return current
    }

    private func reorder(current: Int?) {
        (order, position) = IPodShuffle.playOrder(
            for: songs, mode: mode, current: current,
            album: { $0.album },
            albumOrder: { a, b in
                if a.album != b.album { return a.album.localizedStandardCompare(b.album) == .orderedAscending }
                if a.disc != b.disc { return a.disc < b.disc }
                return a.track < b.track
            },
            using: &random)
    }
}
```

Use the queue like this (`albumSongs` is your list of `Song` values):

```swift
let queue = Queue()
queue.setMode(.albums)
queue.play(albumSongs, startingAt: 3)   // the selected song plays first
queue.setMode(queue.mode.next)          // the shuffle button: Off → Songs → Albums
```

## 7. Test values

Use these values to make sure that a copy is correct. The first two rows come from the unchanged iPod firmware in the emulator, with the seed set to 0x12345678. The test library had 60 songs in 6 albums of 10 songs (database positions 0–59, album k = positions 10(k − 1) … 10k − 1).

| Test | Seed | Result |
|---|---|---|
| Songs, 60 songs, no current song | 0x12345678 | Positions 27, 10, 51, 35, 41, 49, 46, 6, 29, 44, 1, 20, 2, 59, 56, 24, 30, 8, 26, 23, 17, 4, 21, 14, 5, 39, 22, 47, 37, 52, 55, 40, 34, 12, 38, 25, 48, 45, 15, 36, 57, 7, 9, 54, 43, 0, 18, 28, 16, 31, 3, 32, 11, 42, 50, 13, 58, 53, 33, 19. State after: 0x6c572db3. |
| Albums, 6 albums of 10 songs, no current song | 0x12345678 | Albums 5, 1, 6, 4, 3, 2, each in its own order. State after: 0x1f0e9102. |
| Generator, three steps | 1 | 16807, 282475249, 1622650073 |
| Songs, 10 songs, current song 4 | 0x12345678 | 4, 2, 8, 0, 9, 6, 1, 7, 5, 3 |
| Albums `A A A B B C C C C "" ""`, current song 6 | 0x12345678 | 5, 6, 7, 8, 10, 9, 0, 1, 2, 3, 4 |
| `ipod_rng_index(60)` with seed 0 (the state stops) | 0 | 59 in this code. The iPod gives 60 (Bug 1). |

The test program for the C code:

```c
#include <assert.h>
#include <stdio.h>
#include "ipod_shuffle.h"

int main(void)
{
    static const int songs60[8] = {27, 10, 51, 35, 41, 49, 46, 6};
    static const int albums6[6] = {5, 1, 6, 4, 3, 2};
    static const int songs10[10] = {4, 2, 8, 0, 9, 6, 1, 7, 5, 3};
    static const int mixed[11] = {5, 6, 7, 8, 10, 9, 0, 1, 2, 3, 4};
    const char *names60[60], *names11[11];
    char buf[6][16];
    int order[60], i;
    ipod_rng r;

    ipod_rng_seed(&r, 1);
    assert(ipod_rng_next(&r) == 16807);
    assert(ipod_rng_next(&r) == 282475249);
    assert(ipod_rng_next(&r) == 1622650073);

    ipod_rng_seed(&r, 0x12345678);
    ipod_shuffle_songs(order, 60, -1, &r);
    for (i = 0; i < 8; i++)
        assert(order[i] == songs60[i]);
    assert((uint32_t)r.state == 0x6c572db3u);

    for (i = 0; i < 6; i++)
        snprintf(buf[i], sizeof buf[i], "Test Album %d", i + 1);
    for (i = 0; i < 60; i++)
        names60[i] = buf[i / 10];
    ipod_rng_seed(&r, 0x12345678);
    assert(ipod_shuffle_albums(order, names60, 60, -1, &r) == 0);
    for (i = 0; i < 6; i++)
        assert(order[i * 10] / 10 + 1 == albums6[i]);
    assert((uint32_t)r.state == 0x1f0e9102u);

    ipod_rng_seed(&r, 0x12345678);
    ipod_shuffle_songs(order, 10, 4, &r);
    for (i = 0; i < 10; i++)
        assert(order[i] == songs10[i]);

    {
        const char *al[11] = {"A", "A", "A", "B", "B", "C", "C", "C", "C", "", ""};
        for (i = 0; i < 11; i++)
            names11[i] = al[i];
    }
    ipod_rng_seed(&r, 0x12345678);
    assert(ipod_shuffle_albums(order, names11, 11, 6, &r) == 0);
    for (i = 0; i < 11; i++)
        assert(order[i] == mixed[i]);

    assert(ipod_seed_locks(0) && ipod_seed_locks(0x7fffffff) && ipod_seed_locks(0x80000001u));
    assert(!ipod_seed_locks(0x80000000u));
    ipod_rng_seed(&r, 0);
    assert(ipod_rng_index(&r, 60) == 59);
    assert(ipod_make_seed(0x5678, 0x1234) == 0x12345678u);
    puts("All checks pass.");
    return 0;
}
```

The test program for the Swift code (`main.swift`, compile it with `IPodShuffle.swift`):

```swift
var r = IPodRandom(seed: 1)
precondition(r.next() == 16807 && r.next() == 282_475_249 && r.next() == 1_622_650_073)
r = IPodRandom(seed: 0x1234_5678)
let s = IPodShuffle.songs(count: 60, current: nil, using: &r)
precondition(Array(s.prefix(8)) == [27, 10, 51, 35, 41, 49, 46, 6])
precondition(UInt32(bitPattern: r.state) == 0x6C57_2DB3)
r = IPodRandom(seed: 0x1234_5678)
let a = IPodShuffle.albums((0..<60).map { "Test Album \($0 / 10 + 1)" }, current: nil, using: &r)
precondition(stride(from: 0, to: 60, by: 10).map { a[$0] / 10 + 1 } == [5, 1, 6, 4, 3, 2])
precondition(UInt32(bitPattern: r.state) == 0x1F0E_9102)
r = IPodRandom(seed: 0x1234_5678)
precondition(IPodShuffle.songs(count: 10, current: 4, using: &r) == [4, 2, 8, 0, 9, 6, 1, 7, 5, 3])
r = IPodRandom(seed: 0x1234_5678)
let names = ["A", "A", "A", "B", "B", "C", "C", "C", "C", "", ""]
precondition(IPodShuffle.albums(names, current: 6, using: &r) == [5, 6, 7, 8, 10, 9, 0, 1, 2, 3, 4])
precondition(IPodRandom.locksUp(0) && IPodRandom.locksUp(0x7FFF_FFFF) && IPodRandom.locksUp(0x8000_0001))
precondition(!IPodRandom.locksUp(IPodRandom.randomSeed()))
r = IPodRandom(seed: 0)
precondition(r.index(below: 60) == 59)
precondition(IPodRandom.seed(a: 0x5678, b: 0x1234) == 0x1234_5678)
print("All checks pass.")
```

## 8. Bugs in the firmware

The code in this document does not copy these bugs. Each bug changes the result only in rare cases.

### Bug 1: an index equal to n

The float32 value of each state from 0x7fffffc0 to 0x7ffffffe is exactly 2³¹. Then u = 1.0 and the index is n. The iPod then swaps with the memory word after the end of the list. The probability is 63 in 2147483646 (approximately 1 in 34 million) for each index. The code here uses n − 1.

### Bug 2: seeds that stop the generator

The seeds 0, 0x7fffffff and 0x80000001 make the state 0x7fffffff. The state then does not change, and each index is n (Bug 1). The probability on the iPod is 3 in 2³² for each start. The code here does not choose these seeds.

### Bug 3: the shuffle in each album

The firmware has a second option that also shuffles the songs in each album. The Settings menu does not set it. This option uses an index from the start of the list, not from the start of the album. Thus a song can play two times and another song can be lost. The code here does not have this option.

### Bug 4: more than 32767 songs

The firmware gives n to the random index as a 16-bit signed value. With more than 32767 songs, n is negative, and the index is wrong. The code here uses the full value of n.

The iPodFirm patch `shuffle-large-library` corrects Bug 1 and Bug 4 on the iPod. With 32767 songs or fewer, the patched iPod gives the same order as before, except in the rare case of Bug 1.

## 9. Limits of this document

These items are not known:

- If the iPod removes the songs that have "skip when shuffling" set in iTunes.
- If the iPod shuffles again at the end of the list when Repeat is All.
- The sort that the iPod uses for Albums mode when the database has no album index.
- What the iPod does with the current list when the user changes the Shuffle setting during playback. The code in this document shuffles the list again and keeps the current song, as when the user selects a song.

The emulator has no audio, so a song selected in a list does not start there. Thus the rule for the current song (sections 3.2 and 3.3) comes from the disassembly only. The Shuffle Songs results come from the disassembly and from the emulator.

The firmware addresses, for people who want to examine the firmware:

| Address (osos 1.3) | Function |
|---|---|
| 0x094440 | The shuffle (Songs and Albums). |
| 0x0e5978 | The random index and the seed. |
| 0x00055c | The read of the seed counter (register 0x60006038). |
| 0x0b3a04 | The Shuffle setting. |
| 0x0b40c4 | The start of a shuffled play list. |
| 0x0bb28c | Smart playlists with "selected by random". |
