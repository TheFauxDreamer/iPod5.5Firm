# The task system of RetailOS 1.3

This note gives the research of the "Other" system of the note
[firmware-systems.md](firmware-systems.md). That system has 1 named part. The
part is the name `Task`. The name is the base class of the tasks of the
firmware.

The note gives the class, the object, the scheduler and the list of the tasks.

The firmware of the iPod Video runs on a single processor with **ThreadX**, the
real-time kernel of Azure RTOS of Microsoft. ThreadX was the kernel of the
firmware of Apple for the iPod. The unit of work is a **task**. The base class
of the tasks has the name `Task`. The name is at 0x100e9d28 in the image of the
osos. The name is next to the names of the exceptions of the processor ("data
abort", "fiq", "_sys_exit"), because the system writes the name of the class in
the table of the exceptions.

> The research found the kernel by the system calls. The function
> `FUN_10084644` is the entry to the kernel. The function takes a structure
> with the number of the call in the first word. The numbers 0x10 to 0x2a are
> the calls of ThreadX. 52 functions of the firmware make a call to the kernel.
> The calls that the research found are the call to make a thread (0x10), the
> call to delete a thread (0x11), the call to stop a thread (0x12), the call to
> make a queue (0x1f), the call to take a semaphore (0x26), the call to give an
> event (0x28) and the call to wait for an event (0x29).
>
> The number of the call of ThreadX is in the first word of the structure. The
> function `FUN_100a622c` uses the number 0x16. The number 0x16 is the call to
> change the thread. The function `FUN_100a612c` uses the number 0x17. The
> number 0x17 is the call to make a thread with a stack. The function
> `FUN_100a6270` uses the number 0x29. The function `FUN_100a6434` uses the
> number 0x28.

## The class of the tasks

The firmware uses a table for each class. The table has the address of the
method of each slot. The constructor of a class sets the first word of the
object to the address of the table.

The table of the base class of the tasks has 14 slots. 56 tables of the image
have 14 slots. 173 of the 222 tables of the classes have the same 2 methods in
the slots 2 and 3. The methods are at 0x222de4 and 0x222de8. These 2 methods
are the destructor and the method of the class. The tables of the tasks are
these tables.

The scheduler calls the slot 0xc of the table. The slot 0xc is the method that
does the work of the task. The code calls the other slots of the tables of the
tasks more often. The most used slots are the slot 0x54 (557 calls), the slot
0x10 (242 calls) and the slot 0xc (197 calls).

## The object of a task

The function `FUN_100c6b90` makes the object of a task. The function puts the
fields in the object.

| The offset | The field |
|---|---|
| +0x00 | The name of the class. The first word of the object is the address of the table of the class. |
| +0x04 | The address of the method of the task. |
| +0x08 | The size of the stack of the task. |
| +0x0c | The priority of the task. |
| +0x10 | The object of the queue of the task. |
| +0x14 | The class of the priority. |

The object of the task has the size 0x18 bytes. The function `FUN_100c7518`
makes the object. The function gives the memory of the kernel.

The function `FUN_1011c808` makes a task. The function has 7 arguments.

| The argument | The value |
|---|---|
| 1 | The name of the task. |
| 2 | The address of the method of the task. |
| 3 | The names of the classes of the task. The names have a space between them. The function splits the text into the words. |
| 4 | The size of the stack of the task. |
| 5 | The priority of the task. |
| 6 | 0 or 1. The value 1 makes the task with a list of the events. |
| 7 | The number of the events. |

The value 0 of the 3rd argument means that the class of the task is the base
class. The function `FUN_100c2764` gives the name of the class. The function
looks the name up in a table of the names of the classes. The table is made at
the start.

The function `FUN_100e9b98` makes the table of the names of the classes. The
function writes the name of the base class and the names of 14 other classes.
The function receives the 14 names in an array on the stack. The array is made
by the code of the start. The function `FUN_1007ca24` calls it.

## The priority

The function `FUN_10116e64` gives the number of the priority class. The
function has 9 classes. The number of a class is the value of the priority.

| The class | The number |
|---|---|
| 0 | 126 |
| 1 | 60 |
| 2 | 52 |
| 3 | 51 |
| 4 | 49 |
| 5 | 48 |
| 6 | 10 |
| 7 | 9 |
| 8 | 8 |

The function `FUN_100c6b90` gives the class of the priority. The function
uses the size of the stack to give the class.

| The class | The size of the stack |
|---|---|
| 0 | 0 |
| 1 | 8 |
| 2 | 0x10 |
| 3 | other |
| 4 | 0x20 |
| 5 | 0x40 |
| 6 | 0x80 |
| 7 | 0xc0 |
| 8 | 0x100 |

## The queue and the scheduler

The firmware uses the queues of ThreadX. The function `FUN_100a0858` puts a
task in the queue. The function makes the object of the entry, gives the entry
the address of the method of the task, the size of the stack, the priority and
the name. The function then puts the entry in the queue of the priority.

The function `FUN_100a612c` makes a queue. The function `FUN_100a622c` puts the
entry in the queue. The function `FUN_100a6270` takes the entry out of the
queue. The function `FUN_100a6434` takes the first entry of the queue of the
priority 0.

The function `FUN_100f162c` is the tick of the scheduler. The function takes
the first task of the queue. The function then calls the slot 0xc of the table
of the class of the task. The function then sets the byte at +0x15 of the task
to 1. The byte says that the task is in the queue.

The function `FUN_101b1d6c` starts the scheduler. The function makes the
queue of the thread. The function puts the tick in the queue of the thread. The
address of the tick is 0x000f162c. The word that holds the address is at
0x101b1dec.

The system of the messages is the same. The function `FUN_100a6434` takes a
message from the queue of the messages. The messages have the type at +0x11 and
the number of the sender at +0x10.

> The research did not measure the order of the queue. The research did not
> find the code that compares the numbers of the priority. The number of the
> class of the priority is the value of the priority. The note does not say
> which class runs first.

## The list of the tasks

The script [make-task-map.py](make-task-map.py) finds each call of the
function `FUN_1011c808`. The script found 33 calls. The table has the name, the
address of the method, the class, the size of the stack, the priority and the
function that makes the task.

| The task | The method | The class | The stack | The priority |
|---|---|---|---|---|
| `ATAWorkLoopTask` | 0x00186b20 | the base class | 0xc0 | 0x800 |
| `ATAWorkLoopIRQTask` | 0x00186c20 | the base class | 0xc0 | 0x800 |
| `DiskReaderTask` | 0x000ccb40 | the base class | 8 | 0x800 |
| `EventManager` | 0x00151ab4 | the base class | 0x10 | at the start |
| `ICAPTPCameraIOTask` | 0x000e09f4 | at the start | 0xc0 | at the start |
| `KeyRepeatTimer` | 0x001abfb0 | the base class | 0x10 | at the start |
| `LoadDataTasks` | 0x001b9b3c | the base class | 0 | at the start |
| `MP3ExampleTask` | 0x0016b044 | the base class | 0x10 | at the start |
| `Photo Import` | 0x001dc844 | the base class | 0 | at the start |
| `Photo Import Database` | 0x00199430 | the base class | 0 | at the start |
| `SearchHelperThread` | 0x00156228 | the base class | 0 | at the start |
| `StreamCacheReadTask` | 0x000e660c | the base class | 8 | 0x4000 |
| `TimeManager` | 0x000d2ff4 | the base class | 0x20 | at the start |
| `TimerEventManager` | 0x001519e8 | the base class | 0x10 | at the start |
| `TrackCacheReadTask` | 0x000e1dbc | the base class | 8 | 0x2000 |
| `USB MSC` | 0x00184558 | at the start | 0x11 | at the start |
| `USB Secondary Interrupt Task` | 0x0010bf94 | at the start | 0x80 | at the start |
| `USBDeviceTask` | 0x00170ea4 | at the start | 0x20 | 0x1000 |
| `VCUpdateTask` | 0x00164d54 | at the start | 0x20 | 0x800 |
| `WindowManager` | 0x00170d0c | the base class | 0x10 | at the start |
| `eAppAsyncIO` | 0x001e3400 | at the start | 0x10 | 0x2800 |
| `eAppMotor` | 0x0024d87c | the base class | 0x10 | 0x3800 |

The other 11 calls of the function make the task with a name or a class that
the code has at the start. The function `FUN_10289578` and the 7 functions at
0x1028beb4 to 0x1028c788 make a task with the name and the class that the
caller has.

> The table of the tasks of the note [firmware-systems.md](firmware-systems.md)
> has 21 tasks. That table is the table of the tasks of the start of the
> firmware at 0x1025d63c. The table of this note has 22 tasks with a name.
> The two tables have different tasks. The table of the start has the tasks
> that the system of the start makes. The table of this note has the tasks
> that the code of the system makes.

## The limits of the research

| The limit | The result |
|---|---|
| The number of the tasks | The script found 33 calls of the function that makes a task. The firmware has more tasks. The tasks that the code of the system makes at the start are not in the table. |
| The class of a task | The 3rd argument of the function has the name of the class only when the name is a constant. The other tasks have the class at the start. The script cannot join the two. |
| The priority of a task | The priority is at the start for 13 of the tasks. The script cannot give the number of the class of the priority. |
| The 14 classes of the base | The function that makes the table of the names receives the 14 names in an array on the stack. The array is made by the code of the start. The research did not find the 14 names. |
| The name of the class of the base | The name `Task` is at 0x100e9d28. The research found the name by the table of the exceptions. |
| The order of the queue | The research did not find the code that compares the numbers of the priority. The note does not say which class runs first. |

## The scripts of the research

| The script | The use |
|---|---|
| [make-task-map.py](make-task-map.py) | Makes the table of the tasks. The script finds each call of the function that makes a task. |
| [make-class-map.py](make-class-map.py) | Makes the list of the tables of the classes and their methods. |
| [make-systems-map.py](make-systems-map.py) | Makes the list of the systems and the table of the tasks of the start. |

The files of the results are in `~/Library/Application Support/iPodFirm/re/retailos-1.3-decompiled/`.
The folder is not in the repository. The folder holds the image of the firmware.

| The file | The content |
|---|---|
| `task-map.tsv` | Each task with its method, its class, its stack and its priority. |
| `task-classes.tsv` | The number of the tasks of each class. |

## The next steps

| The step | The work |
|---|---|
| 1 | Find the 14 names of the classes that derive from `Task`. The names are in the array that the code of the start makes. The research must read the code of the start. |
| 2 | Give the class of each task. The class of a task is the name at the 3rd argument. The script must follow the value of the argument to the start of the code. |
| 3 | Join the table of the tasks of this note with the table of the tasks of the start. The two tables have the tasks of the system. |
| 4 | Name the calls of the kernel. The function `FUN_10084644` is the entry to the kernel. The function takes the number of the call. The script must read the number and give the name of the call of ThreadX. |
