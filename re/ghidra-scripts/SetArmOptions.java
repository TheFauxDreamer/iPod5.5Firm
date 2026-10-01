// Pre-script for analyzeHeadless: turns on the ARM option that finds more code in a raw binary.
// @category iPodFirm

import ghidra.app.script.GhidraScript;

public class SetArmOptions extends GhidraScript {
    @Override
    protected void run() throws Exception {
        setAnalysisOption(currentProgram, "ARM Aggressive Instruction Finder", "true");
    }
}
