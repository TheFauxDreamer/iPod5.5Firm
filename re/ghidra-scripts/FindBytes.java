// Finds byte patterns in the program, as lines of text:
//   pattern-index<TAB>address<TAB>function<TAB>instruction
// Arguments: OUTPUT_FILE PATTERN [PATTERN ...]
//   A PATTERN is hexadecimal bytes in memory order, with or without spaces. "??" is any byte.
//     Example: "18 10 94 e5" or "1810??e5". An ARM word 0xe5941018 is "18 10 94 e5" in memory.
//   "text:ABC" finds the ASCII bytes of ABC. Use "_" for a space in the text.
// The last line for each pattern gives the count of matches. MakeSignature.java makes patterns.
// @category iPodFirm

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.mem.MemoryBlock;

import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;

public class FindBytes extends GhidraScript {

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        PrintWriter out = new PrintWriter(args[0], "UTF-8");
        out.println("# pattern\taddress\tfunction\tinstruction");
        Memory mem = currentProgram.getMemory();
        for (int p = 1; p < args.length; p++) {
            byte[][] pm = parse(args[p]);
            byte[] bytes = pm[0], mask = pm[1];
            int count = 0;
            for (MemoryBlock b : mem.getBlocks()) {
                if (!b.isInitialized()) {
                    continue;
                }
                Address a = b.getStart();
                while (a != null && !monitor.isCancelled()) {
                    Address hit = mem.findBytes(a, b.getEnd(), bytes, mask, true, monitor);
                    if (hit == null) {
                        break;
                    }
                    Function f = getFunctionContaining(hit);
                    Instruction ins = getInstructionAt(hit);
                    out.printf("%d\t%s\t%s\t%s%n", p, hit, f != null ? f.getName() + "@" + f.getEntryPoint() : "-",
                            ins != null ? ins.toString() : "-");
                    count++;
                    a = hit.compareTo(b.getEnd()) < 0 ? hit.add(1) : null;
                }
            }
            out.printf("# pattern %d \"%s\": %d match(es)%n", p, args[p], count);
        }
        out.close();
    }

    /** Returns {bytes, mask}. A mask byte of 0 means "any byte". */
    static byte[][] parse(String s) {
        if (s.startsWith("text:")) {
            byte[] t = s.substring(5).replace('_', ' ').getBytes(StandardCharsets.US_ASCII);
            byte[] m = new byte[t.length];
            java.util.Arrays.fill(m, (byte) 0xff);
            return new byte[][] { t, m };
        }
        String h = s.replace(" ", "");
        if (h.length() % 2 != 0) {
            throw new IllegalArgumentException("The pattern has an odd count of hexadecimal digits: " + s);
        }
        byte[] b = new byte[h.length() / 2], m = new byte[h.length() / 2];
        for (int i = 0; i < b.length; i++) {
            String pair = h.substring(2 * i, 2 * i + 2);
            if (pair.equals("??")) {
                b[i] = 0;
                m[i] = 0;
            } else {
                b[i] = (byte) Integer.parseInt(pair, 16);
                m[i] = (byte) 0xff;
            }
        }
        return new byte[][] { b, m };
    }
}
