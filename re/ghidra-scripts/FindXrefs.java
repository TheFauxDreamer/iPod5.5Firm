// Writes each reference to the given addresses, as lines of text:
//   target<TAB>from<TAB>reference-type<TAB>function<TAB>instruction
// Arguments: OUTPUT_FILE ADDRESS [ADDRESS ...]   (addresses in hexadecimal)
// Ghidra records only the references that the analysis found. A value in a register or in a
// table that the analysis did not follow is not a reference. Use FindConstant.java for these.
// @category iPodFirm

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.symbol.Reference;

import java.io.PrintWriter;

public class FindXrefs extends GhidraScript {

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        PrintWriter out = new PrintWriter(args[0], "UTF-8");
        out.println("# target\tfrom\ttype\tfunction\tinstruction");
        for (int i = 1; i < args.length; i++) {
            Address target = toAddr(Long.parseLong(args[i].replace("0x", ""), 16));
            int count = 0;
            for (Reference r : getReferencesTo(target)) {
                Address from = r.getFromAddress();
                Function f = getFunctionContaining(from);
                Instruction ins = getInstructionAt(from);
                out.printf("%s\t%s\t%s\t%s\t%s%n", target, from, r.getReferenceType(),
                        f != null ? f.getName() + "@" + f.getEntryPoint() : "-",
                        ins != null ? ins.toString() : "-");
                count++;
            }
            if (count == 0) {
                out.printf("%s\t-\tnone\t-\t-%n", target);
            }
        }
        out.close();
    }
}
