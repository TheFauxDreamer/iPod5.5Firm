#!/bin/zsh
# Decompile the whole osos image of RetailOS 1.3 and map the strings of every
# function.
#
# The script does 3 steps.
#
# 1. The script analyses the image with Ghidra. The analysis gives every
#    string of the image a data item. The script then gives every word that
#    holds the address of a string the type of a pointer. The decompiler
#    follows a pointer. The decompiler then names every string that a function
#    uses.
#
# 2. The script decompiles every function. The output is one block per
#    function.
#
# 3. The script reads the decompiled code and the image. The script makes the
#    map of the strings and the functions.
#
# The script needs Ghidra 12.1.4 and a JDK 21. The script needs the bridge of
# REA. The bridge is in the clone of REA. The script needs the image of the
# osos. The image is at the path in the variable OSOS below.
#
# Usage: ./decompile-with-strings.sh [OUTDIR]
set -e

HERE=${0:A:h}
OUTDIR=${1:-$HOME/Library/Application\ Support/iPodFirm/re/retailos-1.3-decompiled}
OSOS="$HOME/Library/Application Support/iPodFirm/re/osos-1.3.bin"
REA=${REA_DIR:-/tmp/rea}
GHIDRA=${GHIDRA_DIR:-$HOME/Library/Application\ Support/iPodFirm/tools/ghidra_12.1.4_PUBLIC}
JAVA=${JAVA_HOME:-$HOME/Library/Application\ Support/iPodFirm/tools/jdk-21.0.12.1+1/Contents/Home}
BRIDGE=/tmp/rea-strings-bridge
PROJ=$(mktemp -d)
BASE=0x10000000

if [ ! -f "$OSOS" ]; then
    echo "no osos image at $OSOS" >&2
    exit 1
fi
if [ ! -d "$REA/bridge/ghidra" ]; then
    echo "no REA bridge at $REA/bridge/ghidra" >&2
    exit 1
fi
if [ ! -x "$GHIDRA/support/analyzeHeadless" ]; then
    echo "no analyzeHeadless at $GHIDRA/support/analyzeHeadless" >&2
    exit 1
fi

export JAVA_HOME
mkdir -p "$OUTDIR"

# Ghidra takes only the last -scriptPath. Put the bridge and the scripts of
# this project in one directory.
rm -rf "$BRIDGE"
cp -R "$REA/bridge/ghidra" "$BRIDGE"
cp "$HERE/ghidra-scripts/DefineStringPointers.java" "$BRIDGE"
cp "$HERE/ghidra-scripts/DecompileWithStrings.java" "$BRIDGE"
trap 'rm -rf "$PROJ"' EXIT

echo "==> analysing the osos"
time "$GHIDRA/support/analyzeHeadless" "$PROJ" rea-project \
    -import "$OSOS" \
    -loader BinaryLoader -loader-baseAddr $BASE \
    -processor "ARM:LE:32:v7" -cspec default \
    -scriptPath "$BRIDGE" \
    -preScript ReaGhidraPrepareRaw.java "ARM:LE:32:v7" $BASE \
    -postScript ReaGhidraNoReturnFix.java

echo "==> giving the words that hold a string the type of a pointer"
"$GHIDRA/support/analyzeHeadless" "$PROJ" rea-project \
    -process osos-1.3.bin -noanalysis \
    -scriptPath "$BRIDGE" \
    -postScript DefineStringPointers.java "$OUTDIR/string-pointers.tsv"

echo "==> decompiling the osos"
time "$GHIDRA/support/analyzeHeadless" "$PROJ" rea-project \
    -process osos-1.3.bin -noanalysis -readOnly \
    -scriptPath "$BRIDGE" \
    -postScript DecompileWithStrings.java "$OUTDIR/osos-strings.c"

echo "==> making the map of the strings"
python3 "$HERE/make-string-map.py" \
    "$OUTDIR/osos-strings.c" "$OSOS" "$OUTDIR"

echo "==> done"
echo "the code is at $OUTDIR/osos-strings.c"
echo "the map of the strings is at $OUTDIR/osos-string-map.tsv"
echo "the names of the functions are at $OUTDIR/osos-function-names.tsv"
echo "the table of the strings is at $OUTDIR/osos-strings.tsv"
