#!/bin/zsh
# Decompile the whole osos image of RetailOS 1.3 with REA and with Ghidra.
#
# The script writes 2 files. The first file is the C code of every function.
# The second file is a list of the functions with the size and the number of
# calls of each function.
#
# The script needs Ghidra 12.1.4 and a JDK 21. The script needs the bridge of
# REA. The bridge is in the clone of REA. The script needs the image of the
# osos. The image is at the path in the variable OSOS below.
#
# Usage: ./decompile-all.sh [OUTDIR]
set -e

HERE=${0:A:h}
OUTDIR=${1:-$HOME/Library/Application\ Support/iPodFirm/re/retailos-1.3-decompiled}
OSOS="$HOME/Library/Application Support/iPodFirm/re/osos-1.3.bin"
REA=${REA_DIR:-/tmp/rea}
GHIDRA=${GHIDRA_DIR:-$HOME/Library/Application\ Support/iPodFirm/tools/ghidra_12.1.4_PUBLIC}
JAVA=${JAVA_HOME:-$HOME/Library/Application\ Support/iPodFirm/tools/jdk-21.0.12.1+1/Contents/Home}
BRIDGE=/tmp/rea-bridge
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

# Ghidra takes only the last -scriptPath. Put the bridge and the script of this
# project in one directory.
rm -rf "$BRIDGE"
cp -R "$REA/bridge/ghidra" "$BRIDGE"
cp "$HERE/ghidra-scripts/DecompileAll.java" "$BRIDGE"

PROJ=$(mktemp -d)
trap 'rm -rf "$PROJ"' EXIT

echo "==> decompiling the osos"
time "$GHIDRA/support/analyzeHeadless" "$PROJ" rea-project \
    -import "$OSOS" \
    -loader BinaryLoader -loader-baseAddr $BASE \
    -processor "ARM:LE:32:v7" -cspec default \
    -readOnly -deleteProject \
    -scriptPath "$BRIDGE" \
    -preScript ReaGhidraPrepareRaw.java "ARM:LE:32:v7" $BASE \
    -postScript ReaGhidraNoReturnFix.java \
    -postScript DecompileAll.java "$OUTDIR/osos.c"

echo "==> writing the index of the functions"
python3 "$HERE/make-function-index.py" "$OUTDIR/osos.c" "$OUTDIR/osos-functions.tsv"

echo "==> done"
echo "the code is at $OUTDIR/osos.c"
echo "the index is at $OUTDIR/osos-functions.tsv"
