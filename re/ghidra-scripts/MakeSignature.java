// Makes a byte signature for an address, to find the same code in a different firmware version.
// Arguments: OUTPUT_FILE ADDRESS [BEFORE] [AFTER]
//   ADDRESS in hexadecimal. BEFORE and AFTER are counts of 4-byte ARM words (default 6 and 6).
// The script reads the words from ADDRESS - 4*BEFORE to ADDRESS + 4*AFTER. It replaces the parts
// that change when code moves with "??":
//   - the 24-bit offset of a "b" or "bl" instruction;
//   - the 12-bit offset of a "ldr"/"str" relative to pc (the literal pool moves with the code);
//   - a word that is an address in the program (a literal pool entry or a table entry).
// Output, one item on each line:
//   pattern   the signature, for FindBytes.java
//   offset    the byte offset of ADDRESS in the pattern
//   matches   the count of matches in this program. Use a signature with exactly 1 match.
//   fixed     the count of bytes that are not "??" and not zero. A signature needs at least 16.
//   warning   only if the signature is not usable.
// If the count is more than 1, run the script again with larger BEFORE and AFTER values.
// @category iPodFirm

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.mem.MemoryBlock;

import java.io.PrintWriter;

public class MakeSignature extends GhidraScript {

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        PrintWriter out = new PrintWriter(args[0], "UTF-8");
        Address at = toAddr(Long.parseLong(args[1].replace("0x", ""), 16));
        int before = args.length > 2 ? Integer.parseInt(args[2]) : 6;
        int after = args.length > 3 ? Integer.parseInt(args[3]) : 6;
        Memory mem = currentProgram.getMemory();
        int n = before + after + 1;
        byte[] bytes = new byte[4 * n], mask = new byte[4 * n];
        StringBuilder pattern = new StringBuilder();
        Address start = at.subtract(4L * before);
        for (int i = 0; i < n; i++) {
            Address a = start.add(4L * i);
            int w = mem.getInt(a);
            int m = 0xffffffff;
            if ((w & 0x0e000000) == 0x0a000000) {
                m = 0xff000000;                        // b, bl: offset changes when the code moves
            } else if ((w & 0x0c0f0000) == 0x040f0000) {
                m = 0xfffff000;                        // ldr/str rX, [pc, #n]: the pool moves
            } else if (mem.contains(toAddr(w & 0xffffffffL)) && (w & 0xffffffffL) > 0x1000) {
                m = 0;                                 // an address: changes between versions
            }
            for (int k = 0; k < 4; k++) {
                int sh = 8 * k;
                bytes[4 * i + k] = (byte) (w >>> sh);
                mask[4 * i + k] = (byte) (m >>> sh);
                pattern.append(((m >>> sh) & 0xff) == 0xff ? String.format("%02x", (w >>> sh) & 0xff) : "??");
            }
            pattern.append(i < n - 1 ? " " : "");
        }
        int matches = 0;
        for (MemoryBlock b : mem.getBlocks()) {
            Address a = b.getStart();
            while (b.isInitialized() && a != null) {
                Address hit = mem.findBytes(a, b.getEnd(), bytes, mask, true, monitor);
                if (hit == null) {
                    break;
                }
                matches++;
                a = hit.compareTo(b.getEnd()) < 0 ? hit.add(1) : null;
            }
        }
        out.println("address\t" + at);
        out.println("pattern\t" + pattern);
        out.println("offset\t" + 4 * before);
        int fixed = 0;
        for (int i = 0; i < mask.length; i++) {
            fixed += mask[i] == (byte) 0xff && bytes[i] != 0 ? 1 : 0;
        }
        out.println("matches\t" + matches);
        out.println("fixed\t" + fixed);
        if (fixed < 16) {
            out.println("warning\tFewer than 16 fixed bytes that are not zero. This is data, probably a table of "
                    + "addresses. Make a signature of the code that the table points to, then use FindConstant.java.");
        } else if (matches != 1) {
            out.println("warning\tThe signature is not unique. Run the script again with larger BEFORE and AFTER values.");
        }
        out.close();
    }
}
