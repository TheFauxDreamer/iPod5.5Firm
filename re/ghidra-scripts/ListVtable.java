// Lists the words of a vtable (or of any table of addresses), as lines of text:
//   slot-address<TAB>byte-offset<TAB>value<TAB>kind<TAB>function
// Arguments: OUTPUT_FILE ADDRESS [COUNT]   (ADDRESS in hexadecimal; COUNT words, default 64)
// Kinds: "function" (the value is the entry of a function), "code" (an instruction, but no
// function), "data" (another address in the program), "zero" (an empty slot), "other" (not an
// address in the program).
// The list stops early after 4 "other" words in sequence: that is usually the end of the table.
// Then the script lists the references to the table. The code that writes the table address
// into an object is usually the constructor of the class.
// To find the vtable slot of a known method, use FindConstant.java with the method address
// (kind "word").
// @category iPodFirm

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.symbol.Reference;

import java.io.PrintWriter;

public class ListVtable extends GhidraScript {

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        PrintWriter out = new PrintWriter(args[0], "UTF-8");
        Address base = toAddr(Long.parseLong(args[1].replace("0x", ""), 16));
        int count = args.length > 2 ? Integer.parseInt(args[2]) : 64;
        Memory mem = currentProgram.getMemory();
        out.println("# slot\toffset\tvalue\tkind\tfunction");
        int others = 0;
        for (int i = 0; i < count && others < 4; i++) {
            Address slot = base.add(4L * i);
            long value = mem.getInt(slot) & 0xffffffffL;
            Address target = toAddr(value);
            String kind, name = "-";
            Function f = value != 0 && mem.contains(target) ? getFunctionAt(target) : null;
            if (value == 0) {
                kind = "zero";                         // an empty slot (a pure virtual method or no method)
            } else if (f != null) {
                kind = "function";
                name = f.getName();
            } else if (mem.contains(target) && getInstructionAt(target) != null) {
                kind = "code";
            } else if (mem.contains(target)) {
                kind = "data";
            } else {
                kind = "other";
            }
            others = kind.equals("other") ? others + 1 : 0;
            out.printf("%s\t0x%x\t0x%08x\t%s\t%s%n", slot, 4 * i, value, kind, name);
        }
        out.println("# references to the table:");
        for (Reference r : getReferencesTo(base)) {
            Function c = getFunctionContaining(r.getFromAddress());
            out.printf("#   %s\t%s\t%s%n", r.getFromAddress(), r.getReferenceType(),
                    c != null ? c.getName() + "@" + c.getEntryPoint() : "-");
        }
        out.close();
    }
}
