// Decompile every function of the program and write the C code to one file.
// The output is one block per function. The block starts with a line that has
// the address and the name of the function.
//
// The program must be analysed before the script runs. The analysis gives the
// strings of the program a name. The decompiler then uses that name for every
// string that the function uses. The name has the text of the string and the
// address of the string.
//
// The script needs the name of the output file. The script writes that file.
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;

import java.io.PrintWriter;

public class DecompileWithStrings extends GhidraScript {

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 1) {
            throw new IllegalArgumentException("Needs the name of the output file");
        }
        PrintWriter out = new PrintWriter(args[0], "UTF-8");
        DecompInterface dec = new DecompInterface();
        dec.openProgram(currentProgram);
        int count = 0;
        int failed = 0;
        FunctionIterator it = currentProgram.getFunctionManager().getFunctions(true);
        while (it.hasNext() && !monitor.isCancelled()) {
            Function f = it.next();
            if (f.isExternal() || f.isThunk()) {
                continue;
            }
            out.printf("/* ==== %s %s ==== */%n", f.getEntryPoint(), f.getName());
            DecompileResults res = dec.decompileFunction(f, 120, monitor);
            if (res.decompileCompleted() && res.getDecompiledFunction() != null) {
                out.println(res.getDecompiledFunction().getC());
            } else {
                failed++;
                out.printf("/* decompile failed: %s */%n", res.getErrorMessage());
            }
            out.println();
            count++;
            if (count % 500 == 0) {
                out.flush();
                println("decompiled " + count);
            }
        }
        out.flush();
        out.close();
        println("done: " + count + " functions, " + failed + " failed");
    }
}
