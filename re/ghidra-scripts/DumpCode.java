// Writes the instructions of the functions that contain the given addresses, as lines of text:
//   address<TAB>bytes<TAB>mnemonic<TAB>operands
// Arguments: OUTPUT_FILE ADDRESS [ADDRESS ...]   (addresses in hexadecimal)
// If no function contains an address, the script writes the 40 instructions that follow it.
// With --range, the arguments are pairs of addresses: the script writes the instructions of the
// whole range and does not look for a function.
// @category iPodFirm

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;

import java.io.PrintWriter;

public class DumpCode extends GhidraScript {

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        PrintWriter out = new PrintWriter(args[0], "UTF-8");
        boolean range = false;
        for (int i = 1; i < args.length; i++) {
            if (args[i].equals("--range")) {
                range = true;
                continue;
            }
            Address a = toAddr(Long.parseLong(args[i].replace("0x", ""), 16));
            if (range) {
                Address b = toAddr(Long.parseLong(args[++i].replace("0x", ""), 16));
                out.printf("// ===== range %s..%s =====%n", a, b);
                dump(out, a, b);
                out.println();
                continue;
            }
            Function f = getFunctionContaining(a);
            out.printf("// ===== asked for %s =====%n", a);
            if (f != null) {
                out.printf("// function %s at %s, end %s%n", f.getName(), f.getEntryPoint(),
                        f.getBody().getMaxAddress());
                Address start = f.getEntryPoint();
                Address end = f.getBody().getMaxAddress();
                dump(out, start, end);
            } else {
                out.printf("// no function; 40 instructions from %s%n", a);
                dump(out, a, a.add(160));
            }
            out.println();
        }
        out.close();
    }

    private void dump(PrintWriter out, Address start, Address end) throws Exception {
        InstructionIterator it = currentProgram.getListing().getInstructions(start, true);
        while (it.hasNext()) {
            Instruction ins = it.next();
            if (ins.getAddress().compareTo(end) > 0) {
                break;
            }
            byte[] bytes = ins.getBytes();
            StringBuilder hex = new StringBuilder();
            for (byte b : bytes) {
                hex.append(String.format("%02x", b));
            }
            StringBuilder ops = new StringBuilder();
            for (int op = 0; op < ins.getNumOperands(); op++) {
                if (op > 0) {
                    ops.append(", ");
                }
                ops.append(ins.getDefaultOperandRepresentation(op));
            }
            out.printf("%s\t%s\t%s\t%s%n", ins.getAddress(), hex, ins.getMnemonicString(), ops);
        }
    }
}
