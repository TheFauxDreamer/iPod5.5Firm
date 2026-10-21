// Define the words that hold the address of a string as pointers.
// The firmware puts the address of a string in a word. The word is often in a
// table. The decompiler does not follow a word that has no data type. This
// script gives the word the type of a pointer. The decompiler then follows
// the word and names the string.
//
// The script scans the memory of the program for the words that hold the
// address of a string. The script creates a pointer at each such word.
//
// The script needs the name of the output file. The script writes the list of
// the pointers that it created to that file.
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.data.DataType;
import ghidra.program.model.data.PointerDataType;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.DataIterator;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.mem.MemoryBlock;

import java.io.PrintWriter;
import java.util.HashMap;
import java.util.Map;

public class DefineStringPointers extends GhidraScript {

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 1) {
            throw new IllegalArgumentException("Needs the name of the output file");
        }
        PrintWriter out = new PrintWriter(args[0], "UTF-8");
        out.println("pointer_address\tstring_address\ttext");

        Memory memory = currentProgram.getMemory();
        Listing listing = currentProgram.getListing();

        // Step 1. Find the address of every string.
        Map<Long, String> strings = new HashMap<Long, String>();
        DataIterator data = currentProgram.getListing().getDefinedData(true);
        while (data.hasNext()) {
            Data item = data.next();
            Object value = item.getValue();
            if (value instanceof String) {
                strings.put(item.getAddress().getOffset(), (String) value);
            }
        }
        println("strings: " + strings.size());

        // Step 2. Find the words that hold the address of a string.
        DataType pointer = PointerDataType.dataType;
        int created = 0;
        int skipped = 0;
        for (MemoryBlock block : memory.getBlocks()) {
            if (!block.isInitialized()) {
                continue;
            }
            long size = block.getSize();
            byte[] bytes = new byte[(int) size];
            memory.getBytes(block.getStart(), bytes);
            for (long index = 0; index + 4 <= size; index += 4) {
                long value = (bytes[(int) index] & 0xffL) |
                    ((bytes[(int) index + 1] & 0xffL) << 8) |
                    ((bytes[(int) index + 2] & 0xffL) << 16) |
                    ((bytes[(int) index + 3] & 0xffL) << 24);
                String text = strings.get(value);
                if (text == null) {
                    continue;
                }
                Address address = block.getStart().add(index);
                try {
                    // The word may already have a data item. The item must go
                    // before the pointer. The decompiler follows a pointer but
                    // does not follow a word without a type.
                    listing.clearCodeUnits(address, address.add(4), false);
                    Data made = listing.createData(address, pointer, 4);
                    if (made != null) {
                        out.println(address + "\t" + Long.toHexString(value) + "\t" + text);
                        created++;
                    }
                }
                catch (Exception e) {
                    skipped++;
                }
            }
        }
        out.flush();
        out.close();
        println("created: " + created);
        println("skipped: " + skipped);
        println("done");
    }
}
