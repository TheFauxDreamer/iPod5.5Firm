# The music and the media of RetailOS 1.3

This note gives the research of the system "The music and the media" of the
note [firmware-systems.md](firmware-systems.md). The system has 7 named parts.
The parts are 6 tasks and the name `VideoDaisyTask`.

The note gives the tasks, the caches of the music, the video processor of
Broadcom and the copy of the photos.

The addresses are the offsets in the image of the osos. The CPU address of the
code is the offset plus 0x10000000. The note uses the offset.

> This note is the research of the decompilation project. The notes of the
> earlier research stay as they are. The note [shuffle.md](shuffle.md) gives the
> shuffle, the note [album-art-v2.md](album-art-v2.md) gives the covers of the
> albums and the note [custom-eq.md](custom-eq.md) gives the equalizer.

## The summary

The iPod Video plays the music and the video. The music is decoded by the
processor of Apple. The video is decoded by the **video processor of
Broadcom**. The firmware talks to the video processor with a small protocol.

The system has 3 parts.

1. The **tasks**. The tasks read the caches of the music and the covers of the
   albums.
2. The **caches**. The cache of the list of the music, the cache of the stream
   and the cache of the memory of the video.
3. The **video processor**. The firmware reads the statistics of the video
   processor and gives it the data of the video.

## The tasks of the system

The table of the tasks of the firmware is at 0x25d63c. The table has 21 tasks.
None of the tasks of this system is in that table. Each task is made at the run
time.

| The task | The name | The function that makes it | The method | The stack | The priority | The events |
|---|---|---|---|---|---|---|
| `ArtworkLoadTask` | 0x2aa7fc | 0x205cfc | 0x205db4 | 0x20 | 0x8000 | 0x32 |
| `MP3ExampleTask` | 0x16b104 | 0x16b0b0 | 0x16b044 | 0x10 | the value at 0x16b0fc << 4 | 100 |
| `PhotoCopyTask` | 0x199ff8 | 0x199f70 | 0x197e98 | 8 | — | — |
| `TcMemManagerThread` | 0x158260 | 0x158124 | — | — | — | — |
| `TrackCacheReadTask` | 0x94974 | 0x9483c | 0xe1dbc | 8 | 0x2000 | 10 |
| `VCUpdateTask` | 0x16522c | 0x165164 | 0x164d54 | 0x20 | 0x800 | 0 |
| `VideoDaisyTask` | 0x500c98 | 0x1419f4 | 0x14165c | 0x20 | 0x1000 | 0x0f |
| `StreamCacheReadTask` | 0x20be64 | 0x20be1c | 0xe660c | 8 | 0x4000 | 0 |

The function 0x11c808 makes the task. The function has 7 arguments. The
arguments are the name, the method, the names of the classes, the size of the
stack, the priority, the flag and the number of the events.

### The task of the covers of the albums

The function 0x205cfc makes the task `ArtworkLoadTask`. The function does
nothing if the byte at +0x73 of the object is not 0. The function makes the
task one time only.

The name of the task is at the image 0x2aa7fc. The method of the task is at
0x205cfc. The note [album-art-v2.md](album-art-v2.md) has the 22 functions of
the covers.

### The task of the example of the player of MP3

The function 0x16b0b0 makes the task `MP3ExampleTask`. The function makes the
task with the priority in the word at 0x16b0fc. The priority is the value of
the word << 4. The number of the events is 100.

The task is the example of the player of MP3 of Apple. The iPod does not use
the task for the play of the music.

### The task of the copy of the photos

The function 0x199f70 makes the task `PhotoCopyTask`. The function makes the
task with the size of the stack 8. The note
[firmware-camera.md](firmware-camera.md) gives the full research of the copy of
the photos.

### The task of the memory of the video

The function 0x158124 makes the thread `TcMemManagerThread`. The function
makes the object of the thread with the function 0x1588a8. The name of the
thread is at the image 0x158260.

The function 0x158124 makes the thread only if the word at 0x15825c is 0. The
function takes the address of the memory and the size of the memory.

### The task of the cache of the list of the music

The function 0x9483c makes the task `TrackCacheReadTask`. The function makes
the task with the size of the stack 8, the priority 0x2000 and the number of
the events 10.

### The task of the video processor

The function 0x1419f4 makes the task `VideoDaisyTask`. The function makes the
task with the size of the stack 0x20, the priority 0x1000 and the number of
the events 0x0f. The name of the task is at the image 0x500c98. The method of
the task is at 0x14165c.

The function 0x1abba0 is not the maker of the task. The function reads the
start time of the video and the frame rate. The function is the method of the
task of the older iPod.

The function 0x1419f4 also makes a task with the size of the stack 0x20, the
priority 0x1000 and the number of the events 0x0f. The function uses the name
"VideoDaisyTask" at 0x500c98.

### The task of the cache of the stream

The function 0x20be1c makes the task `StreamCacheReadTask`. The function makes
the task with the size of the stack 8, the priority 0x4000 and the number of
the events 0. The name of the task is at the image 0x20be64.

## The copy of the stream

The function 0x1ddc50 makes the 2 tasks of the copy of the stream. The
function calls the function 0x1bf90c for the name of the task of the read and
for the name of the task of the write. The names are at the image 0x1ddc88 and
0x1ddc8c.

| The task | The name |
|---|---|
| `StreamCopierReadTask` | 0x500b74 |
| `StreamCopierWriteTask` | 0x500b5c |

The function sets the byte at 0x1ddc90 plus the number of the task to 0.
## The video processor of Broadcom

The video processor of Broadcom has the name "Daisy" in the code. The firmware
talks to the processor with a small protocol. The protocol is the same for the
audio and for the video.

### The statistics of the video processor

The function 0x1f9754 reads the statistics of the processor. The function takes
the number of the stream at +4. The value 0 is the audio and the value 1 is the
video. The function writes the statistics in the buffer of 0x70 bytes at +8.

The function calls the function 0x11ca20 with the size 0x400 to make the
buffer of the command. The function then calls the function 0x287664 to send
the command and the function 0x287250 to read each value.

The command is the name of the statistics. The name of the audio is
"mp_get_stats audio" at 0x1f9980. The name of the video is "mp_get_stats video"
at 0x1f996c.

| The offset | The name of the value |
|---|---|
| +0x00 | "last_frame_time" |
| +0x04 | "num_frame_buffers" |
| +0x08 | "max_decoded_buffer" |
| +0x0c | "min_decoded_buffer" |
| +0x10 | "lost_frame_asserts" |
| +0x14 | "lost_frame_assert_discards" |
| +0x18 | "lost_frame_assert_overflow" |
| +0x1c | "lost_frame_assert_starvation" |
| +0x20 | "lost_frame_assert_packetorder" |
| +0x24 | "lost_frame_assert_decoding" |
| +0x28 | "total_bytes_decoded" |
| +0x2c | "max_decoded_bytes" |
| +0x30 | "min_time_ahead" |
| +0x34 | "max_time_ahead" |
| +0x38 | "buffering_transistions" |
| +0x3c | "last_displayed_frame" |
| +0x40 | "Disp key_frame" |
| +0x44 | "Disp time" |
| +0x48 | "Disp seq_num" |
| +0x4c | "Disp num_bytes" |
| +0x50 | "Disp decoded data" |
| +0x54 | "Disp param1" |

The names of the values are at the image 0x1f9994 to 0x1f9b50. The name
"no_video" is at 0x1fa540.

### The MP4

The firmware has an MP4 parser. The strings of the parser are at the image
0x1ca110 and 0x1ca758. The parser reads the boxes of the MP4. The names of the
boxes are in the strings. The names have no separator. The parser reads the
names of 4 bytes at a time.

| The offset | The boxes |
|---|---|
| 0x1ca110 | trak, elst, tkhd, mdhd, stts, stsd, stco, stsz, stsc, stss, mp4v, avc1 |
| 0x1ca758 | elst, tkhd, mdhd, stsd, stts, stsz, stsc, stco, mp4a |

The string "mp4 " is at the image 0x1cddec and 0x1ce214.

## The limits of the research

| The limit | The result |
|---|---|
| The video processor of Broadcom | The research found the protocol of the statistics of the processor and the MP4 parser. The programs of the processor are in the image `rsrc`. The research did not analyse the programs. |
| The task `VideoDaisyTask` | The function 0x1abba0 makes the task. The research did not trace the work of the task. |
| The task `MP3ExampleTask` | The function 0x16b0b0 makes the task. The iPod does not use the task. The research did not trace the work of the task. |
| The caches of the music | The research found the 4 tasks of the caches. The research did not trace the work of the tasks. |
| The equalizer of the audio | The note [custom-eq.md](custom-eq.md) has 39 functions. The rest has no note. |

## The sources

- The image of the osos: `~/Library/Application Support/iPodFirm/re/osos-1.3.bin`
- The decompiler: Ghidra 12.1.4, with the script `DecompileAt.java` of the folder [ghidra-scripts](ghidra-scripts)
- The note of the shuffle: [shuffle.md](shuffle.md)
- The note of the covers: [album-art-v2.md](album-art-v2.md)
- The note of the camera: [firmware-camera.md](firmware-camera.md)
