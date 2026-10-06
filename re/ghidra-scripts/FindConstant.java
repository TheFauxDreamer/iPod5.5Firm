// Finds the places where the program uses the given values, as lines of text:
//   value<TAB>kind<TAB>address<TAB>function<TAB>instruction
// Arguments: OUTPUT_FILE [--half] VALUE [VALUE ...]
//   VALUE is hexadecimal with "0x" (0x6421) or decimal with an optional sign (-140).
//   --half also finds 16-bit values on a 2-byte boundary (for example a resource ID in a Menu
//   item). A small value gives many results with --half.
// Kinds:
//   immediate  an instruction operand has the value (for example "mov r1, #0x30")
//   literal    an instruction loads the value from a literal pool ("ldr r0, [pc, #n]")
//   word       a 32-bit word in memory has the value (a table, a vtable or a literal pool)
//   half       a 16-bit value in memory (only with --half)
// ARM code cannot put most 16-bit and 32-bit values in one instruction. The compiler loads them
// from a literal pool, or makes them with two instructions ("mov" then "orr" or "add"). The
// second form is not found. Search for the two parts if you find no result.
// @category iPodFirm

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.scalar.Scalar;
import ghidra.program.model.symbol.Reference;

import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.List;

public class FindConstant extends GhidraScript {
    private PrintWriter out;

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        out = new PrintWriter(args[0], "UTF-8");
        boolean half = false;
        List<Long> values = new ArrayList<>();
        for (int i = 1; i < args.length; i++) {
            if (args[i].equals("--half")) {
                half = true;
            } else if (args[i].startsWith("0x") || args[i].startsWith("0X")) {
                values.add(Long.parseLong(args[i].substring(2), 16));
            } else {
                values.add(Long.parseLong(args[i]));
            }
        }
        out.println("# value\tkind\taddress\tfunction\tinstruction");
        Memory mem = currentProgram.getMemory();

        InstructionIterator it = currentProgram.getListing().getInstructions(true);
        while (it.hasNext() && !monitor.isCancelled()) {
            Instruction ins = it.next();
            for (int op = 0; op < ins.getNumOperands(); op++) {
                for (Object o : ins.getOpObjects(op)) {
                    if (o instanceof Scalar s) {
                        for (long v : values) {
                            if (s.getSignedValue() == v || s.getUnsignedValue() == (v & 0xffffffffL)) {
                                emit(v, "immediate", ins.getAddress());
                            }
                        }
                    }
                }
            }
            for (Reference r : ins.getReferencesFrom()) {
                if (!r.getReferenceType().isRead() || !mem.contains(r.getToAddress())) {
                    continue;
                }
                long word;
                try {
                    word = mem.getInt(r.getToAddress()) & 0xffffffffL;
                } catch (Exception e) {
                    continue;
                }
                for (long v : values) {
                    if (word == (v & 0xffffffffL)) {
                        emit(v, "literal", ins.getAddress());
                    }
                }
            }
        }

        for (MemoryBlock b : mem.getBlocks()) {
            if (!b.isInitialized()) {
                continue;
            }
            Address end = b.getEnd();
            int step = half ? 2 : 4;
            for (Address a = b.getStart(); a.add(3).compareTo(end) <= 0 && !monitor.isCancelled(); a = a.add(step)) {
                if (a.getOffset() % 4 == 0) {
                    long word = mem.getInt(a) & 0xffffffffL;
                    for (long v : values) {
                        if (word == (v & 0xffffffffL)) {
                            emit(v, "word", a);
                        }
                    }
                }
                if (half) {
                    int h = mem.getShort(a) & 0xffff;
                    for (long v : values) {
                        if (v >= -0x8000 && v <= 0xffff && h == (v & 0xffff)) {
                            emit(v, "half", a);
                        }
                    }
                }
            }
        }
        out.close();
    }

    private void emit(long v, String kind, Address a) {
        Function f = getFunctionContaining(a);
        Instruction ins = getInstructionAt(a);
        out.printf("%s\t%s\t%s\t%s\t%s%n", v < 0 ? Long.toString(v) : String.format("0x%x", v), kind, a,
                f != null ? f.getName() + "@" + f.getEntryPoint() : "-", ins != null ? ins.toString() : "-");
    }
}
