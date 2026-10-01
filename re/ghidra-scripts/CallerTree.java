// Writes the caller tree of functions, to a given depth, as lines of text:
//   depth<TAB>entry<TAB>body-start<TAB>body-end<TAB>name<TAB>call-site
// Arguments: OUTPUT_FILE DEPTH ADDRESS [ADDRESS ...]   (addresses in hexadecimal)
// @category iPodFirm

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;

import java.io.PrintWriter;
import java.util.HashSet;
import java.util.Set;

public class CallerTree extends GhidraScript {
    private PrintWriter out;
    private final Set<Function> seen = new HashSet<>();

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        out = new PrintWriter(args[0], "UTF-8");
        int depth = Integer.parseInt(args[1]);
        for (int i = 2; i < args.length; i++) {
            Function f = getFunctionContaining(toAddr(Long.parseLong(args[i].replace("0x", ""), 16)));
            if (f != null) {
                walk(f, 0, depth, "-");
            }
        }
        out.close();
    }

    private void walk(Function f, int level, int max, String site) {
        out.printf("%d\t%s\t%s\t%s\t%s\t%s%n", level, f.getEntryPoint(), f.getBody().getMinAddress(),
                f.getBody().getMaxAddress(), f.getName(), site);
        if (level >= max || !seen.add(f)) {
            return;
        }
        for (Reference r : getReferencesTo(f.getEntryPoint())) {
            Function c = getFunctionContaining(r.getFromAddress());
            if (c != null) {
                walk(c, level + 1, max, r.getFromAddress().toString());
            }
        }
    }
}
