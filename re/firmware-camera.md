# The camera and the USB of RetailOS 1.3

This note gives the research of the system "The camera and the USB" of the note
[firmware-systems.md](firmware-systems.md). The system has 3 named parts. The
parts are the names `ICAPTPCameraIOTask`, `ICAType4CameraDriver` and
`PTPCameraDriver`.

The note gives the drivers, the tables of the classes, the task of the camera
and the path of the import of the pictures.

The addresses are the offsets in the image of the osos. The CPU address of the
code is the offset plus 0x10000000. The tables of the image store the offsets
of the code, not the CPU addresses. The note uses the offset.

## The summary

The iPod Video has no camera. The firmware of the iPod Video has the code of
the camera of the iPod Photo. The code came with the USB host stack of the
Camera Connector of 2005.

The code has two parts.

1. The class drivers of the USB host stack. The stack is the stack of the Mac
   OS 9 USB family of Apple. The stack has a driver for the hub, a driver for
   the storage, a driver for the camera of the type 4 and a driver for the
   camera of the protocol of the pictures (PTP).
2. The service of the camera. The service is the task `ICAPTPCameraIOTask`. The
   task does the requests of the USB stack and gives the answers to the
   application.

The task is not in the table of the tasks of the start. The task is made at the
run time when the host stack starts.

## The class drivers of the USB host stack

The list of the class drivers is at 0x6bc3dc. The list has entries of 44 bytes.
Each entry has the address of the record of the driver at +0 and the address of
the table of the methods at +4. The other fields of the entry are 0 in the
image. The addresses are the addresses in the RAM.

| The entry | The record in the RAM | The table in the RAM | The driver |
|---|---|---|---|
| 0 | 0x1084a444 | 0x1084a484 | the hub |
| 1 | 0x1084a308 | 0x1084a348 | the composite device, the class 0 |
| 2 | 0x1084a360 | 0x1084a348 | the composite device, the class 2 |
| 3 | 0x1084a49c | 0x1084a4dc | the storage |
| 4 | 0x1084a5f4 | 0x1084a634 | the camera of the type 4 |
| 5 | 0x1084a64c | 0x1084a68c | the camera of the protocol of the pictures |

The RAM copy of the RW data starts at the image 0x67e2a8 and the RAM address
0x10800004. The image 0x6c8898 is the RAM 0x1084a5f4. The record of the camera
of the type 4 is thus at the image 0x6c8898.

The two composite entries have the same table of the methods. The table accepts
each device.

## The record of a driver

The record of a driver has the format of the `USBDriverDescription` of the Mac
OS 9 USB family. The tag "usbd" is at the start of the record. The tag is at
the image 0x6c86e8 for the hub.

| The offset | The field |
|---|---|
| +0x00 | The tag "usbd" (4 bytes). |
| +0x08 | The number of the vendor. |
| +0x10 | The values that the device must have. |
| +0x14 | The name of the driver. The name is a string with 1 byte for the length. |

The values at +0x10 hold the class, the subclass and the protocol of the
device. The values are in the order: the class at +0x10, the subclass at +0x11,
the protocol at +0x12.

| The driver | The record | The class | The subclass | The protocol | The vendor |
|---|---|---|---|---|---|
| the hub | 0x6c86e8 | 9 | 0 | 0 | 0 |
| the storage | 0x6c8740 | 8 | 0 | 0 | 0 |
| the camera of the type 4 | 0x6c8898 | 0 | 0 | 0 | 0x04a9 |
| the camera of the pictures | 0x6c88f0 | 6 | 1 | 1 | 0 |

The vendor 0x04a9 is the number of Apple. The driver of the type 4 accepts only
the devices of Apple. The driver of the pictures accepts each device of the
class 6 (the still image), the subclass 1 and the protocol 1.

## The table of the methods of a driver

The table of the methods has the version 0x1100 in the first word. The version
is the same for each table. The next words are the addresses of the methods.
The table has 5 methods for each camera driver.

| The slot | The work |
|---|---|
| +0x04 | The driver accepts the device. |
| +0x08 | The driver opens the device. |
| +0x0c | The driver opens an interface of the device. |
| +0x10 | The driver closes the device. |
| +0x14 | The driver starts the device. |

The probe patch [usb-host-probe](../patches/usb-host-probe) uses the same
layout. The note of the patch calls the slots 1 "validate hardware", 2
"initialize device" and 3 "initialize interface".

| The driver | The table | The accept | The open | The interface | The close | The start |
|---|---|---|---|---|---|---|
| the hub | 0x6c8728 | 0x0e7c40 | 0x0e7bc4 | 0x0df274 | 0x0e7bd4 | — |
| the storage | 0x6c8780 | 0x102194 | 0x102178 | 0x10dd00 | 0x0f4b98 | 0x102190 |
| the camera of the type 4 | 0x6c88d8 | 0x113a78 | 0x118514 | 0x1190a4 | 0x110868 | 0x10d86c |
| the camera of the pictures | 0x6c8930 | 0x110620 | 0x1174d8 | 0x118b50 | 0x10d580 | 0x105c1c |

The table of the hub has only 4 methods. The word at +0x0c is 0. The word at
+0x10 is the method that removes a device from the hub. The method 0x0e7bd4
takes the number of the operation at +0, the number of the port at +2, the
number of the device at +3 and the object of the hub at +0x10.

The method 0x0e7c40 accepts the hub. The method reads the descriptor of the
device at +4. The method accepts the device if the class at +4 is 9 and the
subclass at +5 is 0.

The method 0x0e7bc4 opens the device. The method calls the function 0xccf18 and
gives 0.

The method 0x102194 of the storage accepts the device. The method reads the
class of the device at +6 and calls the function 0xa39e0. The function accepts
the class 0, the class 1 and the class 0x50.

## The class of the object of a camera

The object of the device of the camera of the type 4 has 4 methods. The
methods are at 0x0e74c0, 0x0ec968, 0x10fa48 and 0x10e2d0. The object of the
device of the camera of the pictures has the same 4 methods.

| The method | The work |
|---|---|
| 0x0e74c0 | The method starts the session of the camera. |
| 0x0ec968 | The method sets the byte of the state of the object. |
| 0x10fa48 | The method reads the number of the pictures of the camera. |
| 0x10e2d0 | The method takes the picture from the camera. |

The method 0x0e74c0 takes the lock of the object at +0x14. The method does
nothing if the byte at +0x1568 is not 0. The byte says that the device is
started. The method calls the function 0x110910, then it calls the function
0xeb034. The method gives the error -5 if the state at +0x94 is not 8. The
method then calls the function 0x10f28c and it gives the error -5 if the state
at +0x94 is not 0x0b. The method copies the answer of the camera to +0x414 of
the object.

The method 0x10fa48 takes the lock of the object. The method calls the
function 0xea604 and then the function 0xeb034. The method gives the error -5
if the state at +0x94 is not 0x0e. The method then calls the function
0x11697c and it writes the answer to +0x454 of the object.

The method 0x10e2d0 takes the lock of the object. The method calls the
function 0xea604 and then the function 0xeb034. The method gives the error -5
if the state at +0x94 is not 0x0e. The method then calls the function
0x10ab54 and then the function 0x1d7f80 for the buffer at +0x1584 of the
object.

The three states of the camera are 8, 0x0b and 0x0e. The state 8 is the start
of the session. The state 0x0b is the session that is open. The state 0x0e is
the session that is ready.

## The driver of the camera of the type 4

The driver of the type 4 is the driver of the Camera Connector of Apple. The
record of the driver has the vendor 0x04a9 of Apple.

The method 0x113a78 accepts the device. The method takes the descriptor of the
device at +8 and calls the function 0x11281c with the number of the vendor and
the number of the product. The function 0x11281c accepts the vendor 0x04a9 and
40 numbers of the product.

| The numbers of the product | The result |
|---|---|
| 0x3041, 0x3043 to 0x3049, 0x304b to 0x304f, 0x3050 to 0x3052, 0x3055 to 0x3058 | the driver accepts the device |
| 0x3042, 0x304a, 0x3053, 0x3054 | the driver refuses the device |
| 0x305c, 0x3060 to 0x3062, 0x3066, 0x306a, 0x306c, 0x306e, 0x3078, 0x307a, 0x307f, 0x3080, 0x3084, 0x30eb, 0x30ee, 0x3101 | the driver accepts the device |

The function 0x113aa4 makes the object of the device. The object has 4 words
for the table of the class. The function takes the number of the vendor and the
descriptor of the device. The function reads the number of the product at +10
of the descriptor. The numbers 0x30eb, 0x30ee and 0x3101 set the byte at
+0x156a of the object to 1. The three numbers are the cameras of the type of
the Camera Connector.

The method 0x118514 accepts the device. The method calls the function
0x113aa4. The method gives the object of the device to the caller.

The method 0x1190a4 opens an interface of the device. The method gives 0. The
camera of the type 4 has no interface of its own. The method gives 0 because
the driver does not use the interface.

The method 0x110868 closes the device. The method calls the function
0x110888. The function gives back the memory of the object, the queues and the
buffers of the object. The function 0x110888 frees the fields at +0x70, +0xe0,
+0xe8, +0xf0 and +0xf8, the queue at +0x14, the list at +0x10 and the object of
the device.

The method 0x10d86c starts the device. The method takes the number of the
operation at +0 and the object of the device at +0x10. The method does nothing
if the number of the operation is not 0x0b. The number 0x0b is the operation
that the stack of the Mac OS 9 uses to start a device.

The method sets the byte at +0x1568 of the object to 1 and sends the
notification 0x12 with the code 3 and the object of the device. The
notification 0x12 is the notification of the USB host. The method then takes
the lock of the object and gives it back. The method gives the error 0xffffe4bf
if the byte at +0x1569 is not 0.

## The driver of the camera of the pictures

The driver of the pictures is the driver of the protocol of the pictures (PTP).
The record of the driver has the class 6, the subclass 1 and the protocol 1.

The method 0x110620 accepts the device. The method gives 0. The driver of the
pictures accepts each device of the class 6.

The method 0x1174d8 opens the device. The method gives 0. The driver of the
pictures uses the device that the method 0x118b50 makes.

The method 0x118b50 opens an interface of the device. The method reads the
descriptor of the device. The method accepts the interface if the class at +5
is 6, the subclass at +6 is 1 and the protocol at +7 is 1. The method then
calls the function 0x110780. The function makes the object of the device. The
object has 4 words for the table of the class. The function reads the number of
the vendor at +8 and the number of the product at +10 of the descriptor.

The method 0x10d580 closes the device. The method calls the function 0x10d5a0.
The function gives back the memory of the tables of the objects at +0x1154 and
+0x115c, the memory of the object of the buffer at +0x113c, the queue at +0x14,
the lists at +0x10, +0x1124 and +0x1128 and the object of the device.

The method 0x105c1c starts the device. The method takes the number of the
operation at +0 and the object of the device at +0x10. The method does nothing
if the number of the operation is not 0x0b.

The method sets the byte at +0x1161 of the object to 1. The method calls the
function 0xd1e70 for the address at +0x1124 if the value at +0xbc is not 0x1000.
The method then sends the notification 0x12 with the code 3, the code 2 and the
object of the device. The code 2 says that the device is a camera of the
protocol of the pictures. The method then takes the lock of the object. The
method gives the error 0xffffe4bf if the byte at +0x1162 is not 0. Otherwise
the method calls the function 0xeb02c for the object of the driver of the type
4.

## The task of the camera

The task of the camera has the name `ICAPTPCameraIOTask`. The name is at the
image 0x0deb4c. The method of the task is at 0x0de9d8.

The task is not in the table of the tasks of the start. The task is made at the
run time by the function 0xde9d8. The function makes the task with the
function 0x11c808. The arguments of the call are the name, the address of the
method, the class of the task, the size of the stack 0xc0, the priority, the
flag 1 and the number 2 of the events.

The function 0xde9d8 runs the work of the task. The order of the work:

1. The function takes the lock of the object at +0x14.
2. The function gives the error -6 if the byte at +0x1161 of the object is not
   0. The byte says that the stack of the USB sends a request to the camera.
3. The function makes the object of the list of the pictures at +0x1180.
4. The function calls the function 0xeb034 if the byte at +0x1160 is 0. The
   function gives 3 if the state of the camera is 1. The function gives the
   error -5 if the state at +0xc4 is not 2.
5. The function makes the task if the task does not exist. The task is made one
   time only. The function 0xe5960 gives the message 0x1a to the task of the
   driver of the camera of the type 4 if the task exists.
6. The function calls the function 0x10a744 if the byte at +0x1164 is 0. The
   function makes the buffer of the pictures. The buffer has 64000 bytes.
7. The function calls the function 0xdd2e0. The function reads the number of
   the pictures of the camera.
8. The function copies the answer of the camera to +0x11e0 of the object.
9. The function calls the function 0xdd15c. The function reads the list of the
   objects of the camera. The function then calls the function 0xfbde4. The
   function reads the list of the numbers of the pictures.

The function gives the lock back at the end. The function sets the byte at
+0x1162 to 1. The byte says that the task has the lock. The function sets the
byte at +0x1164 to 1 if the work was without an error.

## The request of the camera

The task sends its requests to the stack of the USB with a service. The
functions of the service are:

| The function | The work |
|---|---|
| 0xdd0dc | The task sends a request and waits for the answer. |
| 0xd5f64 | The task reads the answer of the stack. |
| 0x11396c | The task asks the stack to give the answer again. |

The object of the camera has the request at +0x1104. The request has 8 bytes.
The function 0x11e4e4 writes a 4-byte value to the request. The function
0xbff2c writes a 2-byte value to the request. The fields of the request are:

| The offset | The field |
|---|---|
| +0x1104 | The request (8 bytes). |
| +0x1108 | The number of the request (2 bytes). |
| +0x110a | The value of the request (2 bytes). |
| +0x110c | The number of the data (4 bytes). |
| +0x1110 | The data of the answer (4 bytes). |
| +0x1114 | The number of the data of the answer (4 bytes). |
| +0x1118 | The answer (4 bytes). |
| +0x111c | The type of the message (4 bytes). |
| +0x1120 | The result of the last request (4 bytes). |

The type of the message has the value 0x0c, 0x10 or 0x18. The value 0x0c is
the request without data. The value 0x10 is the request with data. The value
0x18 is the request with the number of the object.

The function 0x100978 makes the request. The function sends the request with
the function 0xdd0dc, then it reads the answer with the function 0xd5f64. The
function copies the data of the answer to the buffer of the caller. The
function sends the data in parts of 0x1000 bytes if the answer is large. The
function reads the number of the objects at the end.

The function 0xe0b2c reads the information of one object of the camera. The
function takes the number of the object and the address of the record of the
object. The record has 0xa4 bytes. The function reads 9 numbers and 2 strings
of the record.

## The path of the import of the pictures

The application does not use the task of the camera. The application uses the
service of the import of the pictures.

| The name | The method | The work |
|---|---|---|
| `Photo Import` | 0x1dcaf0 | The service of the import. |
| `Photo Import Database` | 0x1998b8 | The service of the database of the import. |
| `PhotoCopyTask` | 0x199f70 | The task that copies the pictures. |
| `Image Capture device` | 0x16c588 | The name of the device of the capture. |
| `Photo Library` | 0x19324c | The library of the pictures. |
| `ImagePresentationEngine` | 0x1fc128 | The engine that shows the pictures. |
| `iMAImageCacheThread` | 0x17256c | The thread of the cache of the pictures. |

The function 0x16c588 gives the name of the device of the capture. The function
gives the name for the numbers 4, 5 and 6. The name is the string "Image
Capture device" at the image 0x16c5f8. The function gives 0 for the number 3
and for the numbers that are not in the list.

The function 0x199f70 starts the task that copies the pictures. The function
makes the task with the function 0x11c808. The name is "PhotoCopyTask" at the
image 0x199ff8. The size of the stack is 8. The function waits for the source
of the pictures, then it gives the picture to the library.

The function 0x1998b8 starts the service of the database of the import. The
name is "Photo Import Database" at the image 0x199924.

## The states of the import

The object of the import has the state in the byte at +0x1c. The function
0x197e70 gives 1 for the states 1 to 5 and for the state 7. The function gives
0 for the states 0, 6 and for the states that are not 8 or more.

| The state | The work |
|---|---|
| 1 | The import waits. |
| 2 | The import reads the camera. |
| 3 | The import copies the pictures. |
| 4 | The import waits for the answer. |
| 5 | The import writes the database. |
| 7 | The import is ready. |

The function 0x19b014 sets the state. The function sends the notification of
the change of the state.

## The channels of the application

The function 0x211ddc gives the name of each channel of the application. The
function has a table of the numbers and the names.

| The number | The channel |
|---|---|
| 0x0d | `Channel PhotoBrowse` |
| 0x0e | `Channel PhotoImporting` |
| 0x10 | `Channel PhotoFileManagement` |
| 0x13 | `Channel USBChannel` |
| 0x17 | `Channel SlideShow` |
| 0x18 | `Channel ImageCache` |
| 0x1b | `Channel DiskImage` |

The names are at the image 0x212098, 0x2120ac, 0x2120d4, 0x212120, 0x2121d8,
0x2121ec and 0x212228.

## The limits of the research

| The limit | The result |
|---|---|
| The order of the slots of the table of the methods | The research uses the order of the note of the probe patch. The research did not find the code of the stack that calls the slots. |
| The task of the camera in the table of the tasks | The task is not in the table of the tasks of the start. The task is made at the run time. The research did not find the code of the start that makes the task. |
| The registers of the camera | The camera has no registers in the firmware. The task sends its requests to the stack of the USB with a service. The camera has no hardware in the iPod Video. |
| The names of the methods of the camera | The names come from the strings of the image. The names of the methods of the classes of the camera are not in the image. |
| The order of the import of the pictures | The research did not trace the path from the screen of the import to the task of the camera. The path uses a service with a queue. |
| The PTP operation numbers | The research did not find the numbers of the operations of the protocol of the pictures in the code of the camera. The camera of the type 4 uses the protocol of the Camera Connector, not the protocol of the pictures. |

## The sources

- The image of the osos: `~/Library/Application Support/iPodFirm/re/osos-1.3.bin`
- The decompiler: Ghidra 12.1.4, with the script `DecompileAll.java` of the folder [ghidra-scripts](ghidra-scripts)
- The note of the USB host: [usb-host.md](usb-host.md)
- The note of the kernel: [firmware-task-system.md](firmware-task-system.md)
