#!/usr/bin/env python3
"""Disassemble the UI script (TCmd 9088, SpiderMonkey 1.5 bytecode).

Read-only research tool. The input is the TCmd resource as a file.

Usage: python3 re/tcmd-dump.py TCMD_FILE [--function ID] [--calls ID] [--find BYTES]
"""
import struct
import sys
from pathlib import Path

# The length of each opcode. A value of 0 has a variable length (switch tables).
THREE = {6, 7, 8, 10, 11, 14, 35, 36, 37, 41, 42, 44, 45, 47, 48, 50, 51, 53, 54, 58, 59, 60, 61, 68, 69, 74, 76, 78,
         80, 84, 85, 86, 87, 88, 91, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 104, 105, 108, 109, 114, 117, 119, 120,
         121, 125, 126, 127, 128, 129}
NAMES = {2: "popv", 5: "return", 6: "goto", 7: "ifeq", 8: "ifne", 12: "dup", 18: "eq", 19: "ne", 32: "not",
         53: "getprop", 54: "setprop", 57: "pushobj", 58: "call", 59: "name", 60: "number", 62: "zero", 63: "one",
         66: "false", 67: "true", 68: "or", 69: "and", 70: "tableswitch", 71: "lookupswitch", 81: "pop", 84: "getarg",
         86: "getvar", 87: "setvar", 88: "uint16", 108: "bindname", 109: "setname"}


TABLE_AT = 0x3BC          # the u32 offsets of the functions
FIRST_FUNCTION = 0xF79
HEADER = 10               # u16 ID, u16 arguments, u16, u16 variables, u16 code length


def functions(t: bytes) -> dict[int, tuple[int, int, int, bytes]]:
    """ID -> (file offset of the code, arguments, variables, code)."""
    offsets = []
    while True:
        v = struct.unpack_from("<I", t, TABLE_AT + 4 * len(offsets))[0]
        if offsets and v <= offsets[-1]:
            break
        offsets.append(v)
    base = TABLE_AT + 4 * len(offsets)
    out = {}
    for o in offsets:
        ident, args, _, nvars, length = struct.unpack_from("<5H", t, base + o)
        at = base + o + HEADER
        out[ident] = (at, args, nvars, t[at:at + length])
    return out


def decode(code: bytes):
    """Yield (offset, opcode, operand). Raises ValueError at a length that does not fit."""
    i = 0
    while i < len(code):
        op = code[i]
        if op == 71:                                  # lookupswitch: default, count, (atom, jump) pairs
            n = struct.unpack_from(">H", code, i + 3)[0]
            yield i, op, n
            i += 5 + 4 * n
        elif op == 70:                                # tableswitch: default, low, high, jumps
            lo, hi = struct.unpack_from(">HH", code, i + 3)
            yield i, op, (lo, hi)
            i += 7 + 2 * (hi - lo + 1)
        elif op in THREE:
            if i + 3 > len(code):
                raise ValueError(f"operand after the end at {i:#x}")
            yield i, op, struct.unpack_from(">H", code, i + 1)[0]
            i += 3
        else:
            yield i, op, None
            i += 1


def text(op: int, arg) -> str:
    name = NAMES.get(op, f"op{op}")
    return name if arg is None else f"{name} {arg:#x}" if isinstance(arg, int) else f"{name} {arg}"


def main() -> None:
    t = Path(sys.argv[1]).read_bytes()
    funcs = functions(t)
    if "--function" in sys.argv:
        at, args, nvars, code = funcs[int(sys.argv[sys.argv.index("--function") + 1], 16)]
        print(f"code at {at:#x}, {args} arguments, {nvars} variables, {len(code)} bytes")
        for i, op, arg in decode(code):
            print(f"  {at + i:#07x}  {text(op, arg)}")
    elif "--calls" in sys.argv:
        ident = int(sys.argv[sys.argv.index("--calls") + 1], 16)
        for f, (at, _, _, code) in sorted(funcs.items()):
            if f < FIRST_FUNCTION:              # the top level has a different layout
                continue
            for i, op, arg in decode(code):
                if op == 59 and arg == ident:
                    print(f"{f:#x} at {at + i:#x}")
    else:
        bad = 0
        for f, (at, _, _, code) in funcs.items():
            try:
                last = None
                for last, op, arg in decode(code):
                    if op in (6, 7, 8, 68, 69):
                        target = last + (arg if arg < 0x8000 else arg - 0x10000)
                        if not 0 <= target <= len(code):
                            raise ValueError(f"jump to {target:#x} at {last:#x}")
            except ValueError as e:
                bad += 1
                print(f"{f:#x} at {at:#x}: {e}")
        print(len(funcs), "functions,", bad, "with errors")


if __name__ == "__main__":
    main()
