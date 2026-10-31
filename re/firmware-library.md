# The library of C of RetailOS 1.3

This note gives the research of the library of C of the firmware. The library
is the part of the system "The library of C and the drivers of the hardware"
of the note [firmware-coverage.md](firmware-coverage.md).

The addresses are the offsets in the image of the osos. The CPU address of the
code is the offset plus 0x10000000. The note uses the offset.

> This note is the research of the decompilation project. The notes of the
> earlier research stay as they are.

## The summary

The firmware has the code of the library of C of the compiler of Apple. The
library has 4 parts.

1. The **strings and the memory**. The functions for the strings and for the
   memory. The functions are at the image 0x7ca24 to 0x7cfdc.
2. The **arithmetic**. The functions for the numbers. The functions are at
   the image 0x7d018 to 0x7df58.
3. The **floating point**. The functions for the numbers of 32 bits. The
   functions are at the image 0x7d1f0 to 0x7d7b4.
4. The **memory of the heap**. The functions for the memory that the program
   asks for. The functions are at the image 0x7a670 to 0x7a7b0.

The library has no strings of its own. The image has the string "malloc" at
the image 0x679ba2 and the string "free" at the image 0xc2b0d. The strings
are in the debug information of the library. The image has no other name of
the library.

## The strings and the memory

| The function | The name | The proof | The callers |
|---|---|---|---|
| 0x7ca44 | `memcmp` | The function compares 2 blocks of bytes. The function returns the difference of 2 bytes. | 49 |
| 0x7cae0 | `memcpy` | The function copies a block of bytes. The function copies 32 bytes at a time. | 545 |
| 0x7cad0 | `memset` | The function fills a block with 1 byte. The function takes the value of the byte. | 19 |
| 0x7cc48 | `memmove` | The function copies a block of bytes. The function copies backwards when the blocks overlap. | 4 |
| 0x7ccd0 | `memset` | The function fills a block with 0. The function writes 32 bytes at a time. | 252 |
| 0x7cd28 | `strncpy` | The function fills the rest of the block with 0. The function takes the number of bytes. | 70 |
| 0x7cd6c | `strcpy` | The function copies a string. The function stops at the zero byte. | 116 |
| 0x7cdd4 | `strncmp` | The function compares 2 strings. The function takes the number of bytes. | 55 |
| 0x7ce4c | `strncpy` | The function copies a string of a number of bytes. The function stops at the zero byte. | 54 |
| 0x7ceb8 | `strlen` | The function returns the word at the address of the string. The word holds the length of the string. | 149 |
| 0x7cfdc | `strcmp` | The function compares 2 strings. The function stops at the zero byte. | 15 |

> The function 0x7ceb8 returns the word at the address of the string. The word
> holds the length of the string. The function does not count the bytes. The
> function is not the function `strlen` of the library of C. The research did
> not find the function `strlen` in the image.

## The arithmetic

| The function | The name | The proof | The callers |
|---|---|---|---|
| 0x7d024 | `__udivsi3` | The function divides 2 numbers of 32 bits. The function uses the shift and the carry. | 1,503 |
| 0x82694 | `__umodsi3` | The function gives the rest of the division of 2 numbers of 32 bits. | 488 |
| 0x7d284 | `__aeabi_ldivmod` | The function divides 2 numbers of 64 bits. The function calls the function 0x7f3cc. The function has the numbers of 64 bits. | 3 |
| 0x7d394 | `__floatdidf` | The function changes a number of 64 bits with a fraction into a number of 32 bits with a fraction. The function reads the exponent at the offset 0x14. | 4 |
| 0x7d018 | `__di3di3` | The function divides 2 numbers of 64 bits. The function calls the function 0x82694 with the numbers 0x3c, 0x3c and 0x18. | 2 |

> The names of the functions of the arithmetic come from the standard of the
> ABI of ARM. The standard of the ABI names the functions `__udivsi3`,
> `__umodsi3`, `__aeabi_idiv` and `__aeabi_ldivmod`. The research matched the
> behaviour of each function to the name in the standard. The function 0x7d018
> is not the function `__aeabi_idiv`. The function divides 2 numbers of 64
> bits.

## The floating point

| The function | The name | The proof | The callers |
|---|---|---|---|
| 0x7d1f0 | `__floatundisf` | The function changes a number of 32 bits without a sign into a number of 32 bits with a fraction. The function uses the exponent at the offset 0x17. | 2 |
| 0x7d1c4 | `__aeabi_fmul` | The function multiplies 2 numbers of 32 bits with a fraction. The function calls the function 0x7f1a4 with the words at the offsets 0x20 and 0x24. | 11 |
| 0x7d4f4 | `__floatdisf` | The function changes a number of 32 bits with a fraction into a number of 64 bits. The function uses the exponent at the offset 0x1e. | 4 |
| 0x7d578 | `__floatdisf` | The function changes a number of 32 bits with a fraction into a number of 64 bits. The function calls the function 0x102a8ebc. | 2 |
| 0x7d5c8 | `__aeabi_fadd` | The function adds 2 numbers of 32 bits with a fraction. The function calls the function 0x102a929c. | 2 |
| 0x7d69c | `__aeabi_fmul` | The function multiplies 2 numbers of 32 bits with a fraction. | 2 |
| 0x7d774 | `__aeabi_fcmp` | The function compares 2 numbers of 32 bits with a fraction. The function uses the exponent at the offset 0x7f000000. | 5 |
| 0x7d7b4 | `__aeabi_fdiv` | The function divides 2 numbers of 32 bits with a fraction. | 2 |

> The library of the floating point of the compiler of Apple is not the library
> of the standard of the ABI of ARM. The names of the standard are the same.
> The research used the behaviour of each function. The functions work with
> numbers of 32 bits with a fraction. The research did not check each function
> of the library. The note gives the functions that the research checked.

## The memory of the heap

| The function | The name | The proof | The callers |
|---|---|---|---|
| 0x7a794 | `malloc` | The function asks for a block of a number of bytes. The function calls the function 0x11ca20 with the flag 1. | 104 |
| 0x7a7b0 | `free` | The function gives a block back. The function calls the function 0x1ac8fc with the flag 1. | 107 |
| 0x7a6b0 | `realloc` | The function changes the size of a block. The function calls the function 0x7f198 to find the size of the block. | 1 |
| 0x7a6fc | `calloc` | The function asks for a block and fills it with 0. The function calls the function 0x7f198 to find the size of the block. | 1 |

> The function 0x25a974 is not the function `malloc`. The function calls the
> function 0x11ca20 with the flag 2. The function makes a block of a different
> kind. The research did not find the name of the flag.

## The limits of the research

| The limit | The result |
|---|---|
| The names of the functions | The library has no strings. The research named the functions that the research checked. The research checked 25 functions. The library has about 300 functions. |
| The name of the function 0x7ceb8 | The function returns the length of a string from the word at the address of the string. The function is not the function `strlen` of the library of C. The research did not find the function `strlen` in the image. |
| The library of the floating point | The library is the library of the compiler of Apple. The research did not check each function. The names come from the standard of the ABI of ARM. |
| The heap | The research found 4 functions of the heap. The library has more functions of the heap. The research did not trace the heap. |
| The drivers of the hardware | The image has the code of the drivers of the hardware of the PP5020 of Apple. The research did not find the names of the drivers. The image has no string with the name of a driver. |

## The sources

- The image of the osos: `~/Library/Application Support/iPodFirm/re/osos-1.3.bin`
- The decompiler: Ghidra 12.1.4, with the script `DecompileAt.java` of the folder [ghidra-scripts](ghidra-scripts)
