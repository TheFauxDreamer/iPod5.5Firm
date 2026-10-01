// Writes the decompiled C code of the functions that contain the given addresses.
// Arguments: OUTPUT_FILE ADDRESS [ADDRESS ...]   (addresses in hexadecimal)
// If no function contains an address, the script makes a function at the nearest
// "stmdb sp!, {..., lr}" instruction before the address.
// @category iPodFirm

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.symbol.Reference;

import java.io.PrintWriter;
import java.util.LinkedHashSet;
import java.util.Set;

public class DecompileAt extends GhidraScript {

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        PrintWriter out = new PrintWriter(args[0], "UTF-8");
        DecompInterface dec = new DecompInterface();
        dec.openProgram(currentProgram);
        Set<Function> done = new LinkedHashSet<>();

        for (int i = 1; i < args.length; i++) {
            Address a = toAddr(Long.parseLong(args[i].replace("0x", ""), 16));
            Function f = getFunctionContaining(a);
            if (f == null) {
                f = makeFunctionBefore(a);
            }
            if (f == null) {
                out.printf("// %s: no function found%n%n", a);
                continue;
            }
            if (!done.add(f)) {
                continue;
            }
            out.printf("// ===== %s at %s (asked for %s) =====%n", f.getName(), f.getEntryPoint(), a);
            out.print("// called from:");
            for (Reference r : getReferencesTo(f.getEntryPoint())) {
                Function c = getFunctionContaining(r.getFromAddress());
                out.printf(" %s%s", r.getFromAddress(), c != null ? "(" + c.getName() + ")" : "");
            }
            out.println();
            out.print("// calls:");
            for (Function c : f.getCalledFunctions(monitor)) {
                out.printf(" %s", c.getName());
            }
            out.println();
            DecompileResults res = dec.decompileFunction(f, 60, monitor);
            out.println(res.decompileCompleted() ? res.getDecompiledFunction().getC() : "// decompile failed: " + res.getErrorMessage());
            out.println();
        }
        out.close();
    }

    /** Look back (max 4 KB) for a push of lr, disassemble from there and make a function. */
    private Function makeFunctionBefore(Address a) throws Exception {
        for (int back = 0; back < 4096; back += 4) {
            Address p = a.subtract(back);
            int word = getInt(p);
            // stmdb sp!, {..., lr} == 0xe92d4xxx with bit 14 (lr) set
            if ((word & 0xffff0000) == 0xe92d0000 && (word & 0x4000) != 0) {
                disassemble(p);
                Function f = createFunction(p, null);
                if (f == null) {
                    f = getFunctionAt(p);
                }
                return f;
            }
        }
        return null;
    }
}
