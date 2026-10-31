# The USB and the computer of RetailOS 1.3

This note gives the research of the system "USB and the computer" of the note
[firmware-systems.md](firmware-systems.md). The system has 17 named parts. The
parts are 11 tasks and 6 other names.

The note gives the tasks of the system, the mode manager, the stack of the
device, the identity of the iPod, the protocol of the accessory and the
registers of the controller.

The addresses are the offsets in the image of the osos. The CPU address of the
code is the offset plus 0x10000000. The note uses the offset.

> This note is the research of the decompilation project. It does not change the
> notes of the earlier research. The note [usb-host.md](usb-host.md) gives the
> host side of the stack. The note [usb-audio.md](usb-audio.md) gives the audio
> over the USB. The note [usb-adapter.md](usb-adapter.md) gives the plan for the
> USB-C adapter. This note gives the device side and the parts that the earlier
> notes do not name.

## The summary

The iPod Video is a USB device. The firmware has the stack of the device of the
Mac OS 9 USB family of Apple. The stack has 4 parts.

1. The **mode manager**. The manager starts the mode of the USB. The modes are
   the idle, the device and the host.
2. The **device stack**. The stack answers the computer. The iPod has 4
   interfaces: the storage, the control, the audio and the HID.
3. The **identity of the iPod**. The number of the vendor is 0x05ac of Apple.
   The number of the product tells the model of the iPod.
4. The **protocol of the accessory**. The protocol is iAP of Apple. The iPod
   talks to the accessory over the accessory port.

## The tasks of the system

The table of the tasks of the firmware is at 0x25d63c. The table has 21 tasks.
11 of the tasks belong to this system.

| The task | The method | The work |
|---|---|---|
| `USBDeviceTask` | 0x170fec | The session of the USB device. The task is made at the run time. |
| `USBStatusTask` | 0x2860e8 | The state of the USB. The task is made by the host start. |
| `USBTaskTimeTask` | 0x2860e8 | The time of the tasks of the USB. The task is made by the host start. |
| `USBAudioTask` | 0x0c75cc | The audio over the USB. |
| `USBPowerSense` | 0x2856a4 | The sense of the power of the USB. |
| `FirewireTask` | 0x284e58 | The FireWire. The iPod Video has no FireWire port. |
| `OptoTask` | 0x284f90 | The optoelectronic sensor of the click wheel. |
| `SerialOptoTask` | 0x28558c | The optoelectronic sensor of the serial port. |
| `AccessoryDetectTask` | 0x284338 | The detection of the accessory of the click wheel. |
| `HPhoneDetTask` | 0x284eb0 | The detection of the headphones. |
| `TopPlugTask` | 0x28564c | The plug at the top of the iPod. |

The methods of the first 3 tasks are not in the table of the tasks. The task
`USBDeviceTask` is made by the mode manager. The tasks `USBStatusTask` and
`USBTaskTimeTask` are made by the host start.

> The host start calls the function 0x11c808 with 4 arguments for the two
> tasks. The function needs 7 arguments. The 3 last arguments are the values
> of the registers. The size of the stack and the priority of the two tasks
> are thus not known. The research did not find the values of the registers at
> the call.

### The task of the device

The function 0x170fec makes the object of the task of the device. The function
makes the task with the function 0x11c808. The name is "USBDeviceTask" at the
image 0x17107c. The size of the stack is 0x20, the priority is 0x1000 and the
number of the events is 3.

The argument of the task is the address of the object of the device as a
decimal text. The function 0x7b240 makes the text.

The method of the task is 0x170f2c. The method has a loop with 3 parts.

1. The method waits for the state 3 at +6 of the object. The state 3 means
   that the USB has the power.
2. The method calls the function 0x24d3c4, then the function 0x24cd34, then the
   function 0x24d49c. The three functions are the start of the device, the
   session and the stop of the device.
3. The method begins again.

The function 0x24d3c4 makes the object of the device. The function calls the
function 0x221278. The function 0x221278 makes the object of the controller.

### The task of the headphones

The method 0x284eb0 reads the state of the headphones. The method calls the
function 0xde4b4 and waits for the change of the state. The method then calls
the function 0x66b08 and the function 0xccee4. The method sends the
notification 0xc if the state changed.

### The task of the accessory

The method 0x284338 of the task `AccessoryDetectTask` calls the function
0x265a74. The function gives 1 if there is an accessory. The method then
calls the function 0x186c74, the function 0x163ffc and the function 0x1641a4.
The three functions make the object of the accessory and register it.

### The task of the plug at the top

The method 0x28564c calls the function 0x266144. The function gives the
accessory of the plug. The method then calls the function 0x1e2b7c, the
function 0x163ffc and the function 0x1641a4.

### The task of the optoelectronic sensor of the serial port

The method 0x28558c calls the function 0x2659d4. The method then reads the
register of the sensor at +8 of the object. The value 0x3f means that the
sensor has no data. The method gives the value to the function 0xc953c.

### The task of the optoelectronic sensor of the click wheel

The method 0x284f90 calls the function 0x232be8. The function reads the
sensor. The method then calls the function 0x2659d4. The method gives the
result to the function 0x144d38.

## The manager of the accessory of the resistor

The task `RsistrAccsryMgr` has the method 0xfebf8. The method reads the
resistance of the accessory of the click wheel with the function 0x266034.

The function 0x266034 gives the state of the accessory.

| The state | The accessory |
|---|---|
| 0 | no accessory |
| 1 | the headphones of the click wheel |
| 3 | the accessory of the serial port |
| 100 | the state 15 of the function 0x28341c |

The function 0x266034 calls the function 0x265164 to get the model of the iPod.
The function 0x265c1c gives the state of the accessory. The function reads
the number of the device with the function 0x28341c. The number 0x0b and the
number 0x0c mean that the accessory is at the serial port.

The method 0xfebf8 sends the notification 0xd if the accessory is gone. The
method sends the notification 0x12 with the value 0x14 if the accessory
changed.

## The mode manager of the USB

The task 0x0b95a4 makes the mode manager. The function makes the object of the
manager with the function 0x184aec. The function registers 3 clients with the
function 0x184ab8.

| The client | The object | The mode |
|---|---|---|
| the idle | 0x24d7a4 | 0 |
| the device | 0x170fec | 1 |
| the host | 0x1422e8 | 2 |

The loop of the task 0x0b95a4:

1. The task waits for the power of the USB with the function 0xfdd38.
2. The task stops the mode 2 if the mode is 2. The function 0x18482c stops a
   mode.
3. The task starts the mode 1 with the function 0x184860.
4. The task waits while the power stays with the function 0x10c06c, then it
   stops the mode 1.

The function 0x184860 starts a mode. The function starts the mode only from the
mode 0. The function stops the client 0, then it starts the client of the
mode.

## The stack of the device

### The object of the controller

The function 0x221278 makes the object of the controller. The object has 34
words for the registers. The function 0x15fd30 fills the words. The function
reads the table of the registers at 0x15fe28.

| The word | The register | The address | The mask |
|---|---|---|---|
| +0x00 | the chip | 0x70000028 | 0xffffffff |
| +0x02 | `USBCMD` | 0xC5000140 | 0x00FF8B7F |
| +0x04 | `USBSTS` | 0xC5000144 | — |
| +0x06 | `USBINTR` | 0xC5000148 | 0x000001FF |
| +0x08 | the control of the frame list | 0xC5000154 | 0xffffffff |
| +0x0a | the control of the frame list | 0xC5000158 | 0xffffffff |
| +0x0c | `PORTSC` | 0xC5000184 | 0x217FF1C4 |
| +0x0e | `OTGSC` | 0xC50001A4 | 0x7F00003B |
| +0x10 | `USBMODE` | 0xC50001A8 | 7 |
| +0x12 | the control of the host | 0xC50001AC | 3 |
| +0x14 | the control of the host | 0xC50001B0 | 0 |
| +0x16 | the control of the host | 0xC50001B4 | 0 |
| +0x18 | the control of the host | 0xC50001B8 | 0 |
| +0x1a | the control of the host | 0xC50001BC | 0 |
| +0x1c | the control of the host | 0xC50001C0 | 0x00010001 |
| +0x1e | the control of the host | 0xC50001C4 | 0x00AF00AF |
| +0x20 | the control of the host | 0xC50001C8 | 0x00AF00AF |

The function 0x15fe6c writes a register. The function does nothing if the value
is the same. The function 0x15fe94 gives back the old value of a register.

The object of the controller also has the interrupt object at +0x104. The
function 0x18a8d8 makes the object. The byte at +8 of the interrupt object is 1.

### The identity of the iPod

The function 0xd85d8 gives the identity of the iPod to the computer. The
function calls the function 0x265164 to get the model of the iPod.

The function calls the function 0x24d1f0 with the number 0x05ac. The number is
the number of the vendor of Apple. The function 0x24d1c0 gives the number of
the product. The function 0x24d1a4 gives the version 2. The function 0x24c5c0
gives the text "Apple" at 0xd86ec.

The number of the product tells the model of the iPod. The function switches on
the model. The model is the high half of the value of the function 0x265164.

| The model | The number of the product | The name |
|---|---|---|
| 4 | 0x1202 | "iPod mini" |
| 5 | 0x1203 | "iPod" |
| 6 | 0x1204 | "iPod" |
| 7 | 0x1205 | "iPod mini" |
| 8 | 0x1206 | "iPod" |
| 9 | 0x1207 | "iPod" |
| 0x0a | 0x1203 | "iPod" |
| 0x0b | 0x1209 | "iPod" |
| 0x0c | 0x120a | "iPod" |
| 0x0d | 0x120a | "iPod" |
| 0x0f | 0x120a | "iPod" |

The models 5, 6 and 0x0a have no separate case. The function gives the number
0x1203 for all of them. The models 0x0a, 0x0e and the models that are not in
the table have the number 0x1203.

The values of the numbers of the product are at the image 0xd86b4 to
0xd86dc. The name of the model 7 is the text "iPod mini" at 0xd86c4. The name
of the other models is the text "iPod" at 0xd86e0.

> The iPod Video is the model 0x0b. Its number of the product is 0x1209.
> The model comes from the function 0x265164. Refer to
> [search-5g.md](search-5g.md#what-the-gate-reads).

### The descriptor of the device

The function 0xcd06c makes the descriptor of the device. The function writes
the fields of the descriptor. The fields are 4 bytes apart.

| The word | The value |
|---|---|
| +0x00 | 0x01000000 |
| +0x04 | the length 0x12 |
| +0x08 | the type 1 |
| +0x14 | 6 |
| +0x18 | the class of the device |
| +0x1c | the subclass 1 |
| +0x20 | the protocol |
| +0x24 | the size of the packet |
| +0x28 | the number of the vendor |
| +0x2c | the number of the product |
| +0x34 | the version of the device |

The function 0xe5f84 makes the descriptor of a configuration. The function
writes the type 3 at the word 1 and the length 0x12 at the word 2. The number
of the interfaces is 6.

The descriptor of 18 bytes that the computer reads is in the object of the
device. The function 0x24d1f0 writes the number of the vendor at +8 and +9 of
the object. The function 0x24d1c0 writes the number of the product at +0xa and
+0xb. The function 0x24d1a4 writes the version at +0xc and +0xd. These
offsets are the offsets of the descriptor of the device of the USB.

### The 4 interfaces of the iPod

The function 0x24d628 makes the object of the interface of the USB. The
function makes 4 objects of interfaces. Each object has a table of the class.

| The object | The table of the class | The work |
|---|---|---|
| 0x1de818 | 0x66a510 | The control of the storage. |
| 0x132614 | — | The audio. |
| 0x24d79c | — | The name of the interface. |

The function calls the method +0x10 of each object. The method puts the
descriptor of the interface into the buffer of the device.

The name of the interface is the text "iPod USB Interface" at 0x24d788.

The task `USB MSC` is the task of the storage. The function 0x18472c makes the
object of the task. The function makes the task with the function 0x11c808. The
name is "USB MSC" at 0x184824. The size of the stack is 0x11. The priority is
in the word at 0x18481c. The number of the events is 10. The function makes 8
objects of the endpoints. Each object has 4 words.

### The task of the storage

The function 0x18472c makes the object of the task of the storage. The object
has a table of the class at 0x66bbac. The table has 6 methods.

| The slot | The method | The work |
|---|---|---|
| +0x00 | 0x1846e4 | The constructor of the object. |
| +0x04 | 0x1846ec | The destructor of the object. |
| +0x10 | 0x184d18 | The start of the task. |
| +0x20 | 0x185210 | The read of the disk. |
| +0x24 | 0x185354 | The write of the disk. |

## The protocol of the accessory

The protocol is iAP of Apple. The iPod sends the data over the accessory port.

The function 0x1fb50c sends the command of the lingo 6. The lingo 6 is the
USB host. The command 3 tells the accessory to change to the host mode. The
function calls the function 0x1242b8 with the lingo 6 and the command 3.

The function 0x1242b8 makes the message. The function 0x124808 puts the message
into the queue of the accessory.

The two threads of the protocol are the tasks of the class `CIapIncomingProcessThread`
and the class `CIapOutgoingProcessThread`. The names are at the image 0x1d6410
and 0x1d7520.

The function 0x1d62d4 makes the thread of the incoming data. The function calls
the function 0x22463c with the name. The function 0x28c494 makes the object of
the thread. The object has 8 words. The function 0x1d6a78 starts the thread.

The function 0x1d73e4 makes the thread of the outgoing data. The function calls
the function 0x28c614. The function 0x1d7704 starts the thread.

The object of the thread of the incoming data is at the RAM 0x108318ec. The
byte at +5 of the object is the flag that stops the session of the device.

## The registers of the controller

The table of the registers is at the image 0x15fe28. The table has the address
of each register. The mask of each register is in the object, not in the
table.

| The address | The name | The mask in the object |
|---|---|---|
| 0x70000028 | the chip | 0xffffffff |
| 0xC5000140 | `USBCMD` | 0x00FF8B7F |
| 0xC5000144 | `USBSTS` | — |
| 0xC5000148 | `USBINTR` | 0x000001FF |
| 0xC5000154 | the control of the frame list | 0xffffffff |
| 0xC5000158 | the control of the frame list | 0xffffffff |
| 0xC5000184 | `PORTSC` | 0x217FF1C4 |
| 0xC50001A4 | `OTGSC` | 0x7F00003B |
| 0xC50001A8 | `USBMODE` | 7 |
| 0xC50001AC | the control of the host | 3 |
| 0xC50001B0 | the control of the host | 0 |
| 0xC50001B4 | the control of the host | 0 |
| 0xC50001B8 | the control of the host | 0 |
| 0xC50001BC | the control of the host | 0 |
| 0xC50001C0 | the control of the host | 0x00010001 |
| 0xC50001C4 | the control of the host | 0x00AF00AF |
| 0xC50001C8 | the control of the host | 0x00AF00AF |

The chip of the controller is at the address 0x70000028. The function 0x15fd30
puts this address in the word 0 of the object.

> The research did not find the names of the 6 registers of the host. The
> addresses are in the table. The names come from the manual of the controller
> of Apple.

## The state of the device

The function 0xc0bb4 answers the requests of the computer. The function reads
the type of the request in the byte at +0 of the message.

| The type | The request |
|---|---|
| 0 | the descriptor of the device. The function copies 18 bytes from +0xc of the message. |
| 1 | the descriptor of the configuration. |
| 2 | the descriptor of the string. The function copies 18 bytes from +0x14 and 9 bytes from +0xc. |
| 3 | the descriptor of the interface. |
| 9 | the request has no answer. The function gives 0xffffffff. |
| 0x0a | the request has no answer. The function gives 0xffffffff. |
| 0x0c | the request has no answer. The function gives 0xffffffff. |
| 0x0d | the control of the endpoint. The function calls the function 0xd3a4c. |
| 0x17 | the interface of the accessory. The function sends the message 5. |
| 0x18 | the answer of the accessory. The function gives 0. |
| 0x19 | the answer of the accessory. The function gives 0. |
| 0x20 | the state of the device. The function writes the value at +0x10 of the message to +0x14 of the object. |
| 0xff | the request has no answer. The function gives 0xffffffff. |

For the type 0 the function compares the number of the vendor at +8 of the copy
with 0x05ac. The function gives the number of the vendor and the number of the
product to the object of the device if the number of the vendor is not 0x05ac
and the number of the product is not 0x8000 or 0x8031. The two numbers are the
root hub of the emulator and the root hub of the real iPod.

The function 0xe34f8 is the state machine of the device. The function reads the
state in the word at +0x18 of the object. The states are 1 to 4.

| The state | The work |
|---|---|
| 1 | The device waits for the address. The function 0x1193d8 reads the address from the register. |
| 2 | The device sets the size of the transfer. The word at +0xdc is 0, 1 or 0x800. The function reads the bits 0x200 and 0x400 of the word at +0xc8. |
| 3 | The device sets the endpoints. The endpoint 0x06 is the control. The endpoint 0x81 is the input. The size of the transfer is 8. |
| 4 | The device makes the other states. |

## The limits of the research

| The limit | The result |
|---|---|
| The number of the product of the iPod Video | The research did not find the model of the iPod Video in the table of the models. The function 0xd85d8 gives the number of the product from the model. |
| The 4 interfaces of the iPod | The research found 4 objects of interfaces. The research did not find the number of the interface and the number of the endpoint of each object. The note of the probe patch has the numbers of the endpoints. |
| The methods of the tables of the classes | The research read the table of the class of the storage and the table of the application. The research did not name each method. |
| The names of the methods of the classes | The names come from the strings of the image. The names of the methods of the classes of the USB are not in the image. |
| The FireWire | The task `FirewireTask` has the method 0x284e58. The iPod Video has no FireWire port. The research did not trace the task. |
| The iAP | The research found the lingo 6 and the command 3. The research did not make a table of all the lingos and the commands. |
| The class of the accessory | The research found the states of the accessory of the resistor. The research did not make a table of all the accessories. |

## The sources

- The image of the osos: `~/Library/Application Support/iPodFirm/re/osos-1.3.bin`
- The decompiler: Ghidra 12.1.4, with the script `DecompileAt.java` of the folder [ghidra-scripts](ghidra-scripts)
- The note of the USB host: [usb-host.md](usb-host.md)
- The note of the audio over the USB: [usb-audio.md](usb-audio.md)
- The note of the kernel: [firmware-task-system.md](firmware-task-system.md)
