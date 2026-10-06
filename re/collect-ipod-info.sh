#!/bin/bash
# collect-ipod-info.sh: collects the firmware data of a connected iPod into one ZIP file, for research.
#
# The script only reads the iPod. It never writes to it. It does not copy music, photos, videos,
# contacts, calendars or notes. Without --library, it does not copy the music library database.
#
# It collects:
#   - the firmware partition (the first partition of the iPod disk), as a .bin file;
#   - the first block of the disk (the partition table);
#   - the device information files in iPod_Control/Device (for example SysInfoExtended);
#   - the disk and USB information from macOS (diskutil and ioreg);
#   - with --library: the files in iPod_Control/iTunes (the library database, without music files).
#
# Usage:
#   bash collect-ipod-info.sh [--disk diskN] [--library] [--no-firmware]
#
# The read of the raw disk needs administrator rights: the script uses sudo and asks for your password.
# Terminal must have Full Disk Access (System Settings > Privacy & Security > Full Disk Access).
#
# Test mode (no iPod, no sudo): IPOD_TEST_IMAGE=disk.img IPOD_TEST_BLOCK=512 [IPOD_TEST_VOLUME=dir] bash collect-ipod-info.sh
set -euo pipefail

VERSION=3
MAX_PARTITION=$((512 * 1024 * 1024))      # a firmware partition is smaller; a larger value is an error
DISK=""
LIBRARY=0
FIRMWARE=1

while [ $# -gt 0 ]; do
    case "$1" in
        --disk) DISK="${2:-}"; shift 2 ;;
        --library) LIBRARY=1; shift ;;
        --no-firmware) FIRMWARE=0; shift ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

fail() { echo "ERROR: $*" >&2; exit 1; }

# -- find the iPod ---------------------------------------------------------------------------------

TEST_IMAGE="${IPOD_TEST_IMAGE:-}"
if [ -n "$TEST_IMAGE" ]; then
    [ -f "$TEST_IMAGE" ] || fail "IPOD_TEST_IMAGE is not a file."
    DISK="test"
    RAW="$TEST_IMAGE"
    BS="${IPOD_TEST_BLOCK:-512}"
    VOLUME="${IPOD_TEST_VOLUME:-}"
    SUDO=()
else
    [ "$(uname)" = "Darwin" ] || fail "This script is for macOS."
    media_name() { diskutil info "$1" 2>/dev/null | sed -n 's/^ *Device \/ Media Name: *//p'; }
    if [ -z "$DISK" ]; then
        FOUND=()
        for d in $(diskutil list external physical 2>/dev/null | awk '/^\/dev\/disk/ {sub("/dev/", "", $1); print $1}'); do
            case "$(media_name "$d" | tr '[:upper:]' '[:lower:]')" in *ipod*) FOUND+=("$d") ;; esac
        done
        [ ${#FOUND[@]} -eq 0 ] && fail "No iPod found. Connect the iPod and make sure that Finder shows it."
        [ ${#FOUND[@]} -gt 1 ] && fail "More than one iPod found (${FOUND[*]}). Connect only one, or use --disk diskN."
        DISK="${FOUND[0]}"
    fi
    case "$(media_name "$DISK" | tr '[:upper:]' '[:lower:]')" in
        *ipod*) ;;
        *) fail "$DISK is not an iPod (media name: \"$(media_name "$DISK")\")." ;;
    esac
    RAW="/dev/r$DISK"
    BS="$(diskutil info "$DISK" | sed -n 's/^ *Device Block Size: *\([0-9]*\) Bytes.*/\1/p')"
    [ -n "$BS" ] || fail "Cannot read the block size of $DISK."
    VOLUME=""
    for s in $(diskutil list "$DISK" | awk '{print $NF}' | grep "^${DISK}s"); do
        m="$(diskutil info "$s" | sed -n 's/^ *Mount Point: *//p')"
        if [ -n "$m" ] && [ -d "$m/iPod_Control" ]; then VOLUME="$m"; break; fi
    done
    SUDO=(sudo)
fi

STAMP="$(date +%Y-%m-%d_%H.%M.%S)"
# Hard limits for the temporary folder. The script removes its files at the end, so:
#  - the script must not run as root (it uses sudo only for the reads of the raw disk);
#  - the temporary folder of the system must be an absolute path, not "/", and must exist;
#  - mktemp makes a new folder with a random name; the name must have the exact pattern.
# At the end, the script never deletes recursively. Refer to remove_temp_files below.
[ "$(id -u)" != 0 ] || fail "Do not start the script with sudo. The script asks for your password when it needs it."
TMPBASE="${TMPDIR:-/tmp}"
TMPBASE="${TMPBASE%/}"
case "$TMPBASE" in
    /?*) ;;
    *) fail "The temporary folder of the system (TMPDIR=\"${TMPDIR:-}\") is not usable." ;;
esac
[ -d "$TMPBASE" ] || fail "The temporary folder of the system (\"$TMPBASE\") does not exist."
WORK="$(mktemp -d "$TMPBASE/ipod-info.XXXXXXXX")" || fail "Cannot make a temporary folder."
case "$WORK" in
    "$TMPBASE"/ipod-info.????????) ;;
    *) fail "Unexpected temporary folder: \"$WORK\"." ;;
esac
[ -d "$WORK" ] && [ "$WORK" != "/" ] || fail "Unexpected temporary folder: \"$WORK\"."
OUT="$WORK/ipod-info-$STAMP"
mkdir -p "$OUT"
echo "==> iPod: $DISK (block size $BS bytes). The files go to a temporary folder first."

# Reads COUNT blocks of BLOCK bytes at block SKIP of the raw disk to standard output. Read only.
read_raw() { ${SUDO[@]+"${SUDO[@]}"} dd if="$RAW" bs="$1" skip="$2" count="$3" 2>/dev/null; }

hex_at() { od -An -tx1 -j"$2" -N"$3" "$1" | tr -d ' \n'; }          # FILE OFFSET COUNT -> hex
le32() { local h; h="$(hex_at "$1" "$2" 4)"; echo $((16#${h:6:2}${h:4:2}${h:2:2}${h:0:2})); }
be32() { local h; h="$(hex_at "$1" "$2" 4)"; echo $((16#$h)); }

# -- information from macOS ------------------------------------------------------------------------

{
    echo "collect-ipod-info.sh version $VERSION"
    echo "date: $STAMP"
    echo "macOS: $(sw_vers -productVersion 2>/dev/null || uname -r)"
    echo "disk: $DISK"
    echo "block size: $BS"
    echo "volume: ${VOLUME:-not mounted}"
    echo "options: library=$LIBRARY firmware=$FIRMWARE"
} > "$OUT/info.txt"
if [ -z "$TEST_IMAGE" ]; then
    diskutil info "$DISK" > "$OUT/diskutil-info.txt" 2>&1 || true
    diskutil list "$DISK" > "$OUT/diskutil-list.txt" 2>&1 || true
    ioreg -p IOUSB -w0 -l -r -n iPod > "$OUT/ioreg-usb.txt" 2>&1 || true
fi

# -- the partition table and the firmware partition ------------------------------------------------

if [ "$FIRMWARE" = 1 ]; then
    echo "==> Reading the partition table (your password can be necessary)."
    read_raw "$BS" 0 1 > "$OUT/block0.bin" || fail "Cannot read $RAW. Give Terminal Full Disk Access, then try again."
    [ -s "$OUT/block0.bin" ] || fail "Cannot read $RAW. Give Terminal Full Disk Access, then try again."
    LBA=""; COUNT_SECTORS=""
    if [ "$(hex_at "$OUT/block0.bin" 510 2)" = "55aa" ]; then
        TYPE0=$((16#$(hex_at "$OUT/block0.bin" 450 1)))
        LBA=$(le32 "$OUT/block0.bin" 454)
        COUNT_SECTORS=$(le32 "$OUT/block0.bin" 458)
        echo "partition table: MBR (Windows format), entry 0 type $TYPE0, start sector $LBA, sectors $COUNT_SECTORS" >> "$OUT/info.txt"
        [ "$TYPE0" = 0 ] || fail "The first partition is not an iPod firmware partition (type $TYPE0)."
    elif [ "$(hex_at "$OUT/block0.bin" 0 2)" = "4552" ]; then                     # "ER": Apple partition map
        MUL=$(( 16#$(hex_at "$OUT/block0.bin" 2 1) / 2 ))
        COUNT=1; BLK=1
        while [ "$BLK" -le "$COUNT" ] && [ "$BLK" -lt 64 ]; do
            OFF=$(( BLK * MUL * 512 ))
            read_raw "$BS" $(( OFF / BS )) 1 > "$OUT/apm-entry.bin"
            E=$(( OFF % BS ))
            [ "$(hex_at "$OUT/apm-entry.bin" "$E" 2)" = "504d" ] || break                 # "PM"
            COUNT=$(be32 "$OUT/apm-entry.bin" $(( E + 4 )))
            if [ "$(hex_at "$OUT/apm-entry.bin" $(( E + 48 )) 10)" = "4170706c655f4d444657" ]; then   # "Apple_MDFW"
                LBA=$(be32 "$OUT/apm-entry.bin" $(( E + 8 )))
                COUNT_SECTORS=$(be32 "$OUT/apm-entry.bin" $(( E + 12 )))
                break
            fi
            BLK=$(( BLK + 1 ))
        done
        rm -f "$OUT/apm-entry.bin"
        echo "partition table: APM (Mac format), Apple_MDFW start sector ${LBA:-none}, sectors ${COUNT_SECTORS:-none}" >> "$OUT/info.txt"
    else
        fail "The partition table is not MBR or APM. Send the file $OUT/block0.bin instead."
    fi
    [ -n "$LBA" ] && [ -n "$COUNT_SECTORS" ] || fail "No firmware partition found."

    # The partition table gives sectors. iPodFirm uses the block size that the system reports as the
    # sector size. Some iPods report a block size that is not the unit of their partition table. Thus
    # try the reported block size first, then 512, 2048 and 4096 bytes. Use the first unit where the
    # partition starts with the Apple STOP banner "{{~~".
    banner_at() {                                   # OFFSET -> success if "{{~~" is at OFFSET
        local first=$(( $1 / BS )) pre=$(( $1 % BS )) n=1
        [ $(( pre + 4 )) -gt "$BS" ] && n=2
        read_raw "$BS" "$first" "$n" > "$OUT/probe.bin" || return 1
        [ "$(hex_at "$OUT/probe.bin" "$pre" 4)" = "7b7b7e7e" ]
    }
    UNIT=""; TRIED=""
    for u in "$BS" 512 2048 4096; do
        case " $TRIED " in *" $u "*) continue ;; esac
        TRIED="$TRIED $u"
        [ $(( COUNT_SECTORS * u )) -le "$MAX_PARTITION" ] || continue
        if banner_at $(( LBA * u )); then UNIT=$u; break; fi
    done
    rm -f "$OUT/probe.bin"
    if [ -n "$UNIT" ]; then
        echo "sector unit: $UNIT bytes (the STOP banner is at the start of the partition)" >> "$OUT/info.txt"
    else
        UNIT=$BS
        echo "sector unit: $BS bytes (no STOP banner found with the units$TRIED)" >> "$OUT/info.txt"
        echo "    WARNING: The firmware partition does not start with the Apple STOP banner. The script continues."
    fi
    START=$(( LBA * UNIT ))
    SIZE=$(( COUNT_SECTORS * UNIT ))
    [ "$SIZE" -gt 0 ] && [ "$SIZE" -le "$MAX_PARTITION" ] || fail "The firmware partition size ($SIZE bytes) is not plausible."

    echo "==> Reading the firmware partition ($((SIZE / 1048576)) MB). This takes some minutes."
    if [ $(( START % BS )) -eq 0 ] && [ $(( SIZE % BS )) -eq 0 ]; then
        CHUNK=$BS
        for k in 2048 256 32; do
            if [ $(( START % (BS * k) )) -eq 0 ] && [ $(( SIZE % (BS * k) )) -eq 0 ]; then CHUNK=$(( BS * k )); break; fi
        done
        read_raw "$CHUNK" $(( START / CHUNK )) $(( SIZE / CHUNK )) > "$OUT/firmware-partition.bin"
    else
        # The partition does not start or end on a block boundary: read whole blocks, then cut.
        PRE=$(( START % BS ))
        read_raw "$BS" $(( START / BS )) $(( (PRE + SIZE + BS - 1) / BS )) > "$OUT/blocks.bin"
        tail -c +$(( PRE + 1 )) "$OUT/blocks.bin" | head -c "$SIZE" > "$OUT/firmware-partition.bin"
        rm -f "$OUT/blocks.bin"
    fi
    GOT=$(wc -c < "$OUT/firmware-partition.bin" | tr -d ' ')
    [ "$GOT" -eq "$SIZE" ] || fail "Short read: $GOT of $SIZE bytes."

    # A short check of the result. The full analysis is done later.
    F="$OUT/firmware-partition.bin"
    {
        echo "firmware partition bytes: $GOT"
        echo "STOP banner: $([ "$(head -c 4 "$F")" = "{{~~" ] && echo yes || echo no)"
        echo "]ih[ magic: $([ "$(hex_at "$F" 256 4)" = "5d69685b" ] && echo yes || echo no)"
        D=$(le32 "$F" 260)
        echo "directory value at 0x104: $D"
        echo "directory at value + 0x200: $(hex_at "$F" $(( D + 512 )) 8)"
        echo "directory at value + 0x1000: $(hex_at "$F" $(( D + 4096 )) 8)"
    } >> "$OUT/info.txt"
fi

# -- files on the iPod volume ---------------------------------------------------------------------

if [ -n "$VOLUME" ] && [ -d "$VOLUME/iPod_Control" ]; then
    echo "==> Copying the device information files."
    if [ -d "$VOLUME/iPod_Control/Device" ]; then
        mkdir -p "$OUT/iPod_Control/Device"
        find "$VOLUME/iPod_Control/Device" -maxdepth 1 -type f -size -2048k ! -name '._*' -exec cp {} "$OUT/iPod_Control/Device/" \;
    fi
    # The names of the folders in iPod_Control, without the names of the music files.
    find "$VOLUME/iPod_Control" -maxdepth 2 -type d ! -path "*/Music/*" | sed "s#^$VOLUME/##" | LC_ALL=C sort > "$OUT/ipod-control-folders.txt"
    if [ "$LIBRARY" = 1 ] && [ -d "$VOLUME/iPod_Control/iTunes" ]; then
        echo "==> Copying the library database (no music files)."
        mkdir -p "$OUT/iPod_Control"
        # Only regular files: find -type f does not follow a link and does not list one.
        (cd "$VOLUME/iPod_Control" && find iTunes -type f ! -name '._*' -print0) |
            while IFS= read -r -d '' f; do
                mkdir -p "$OUT/iPod_Control/$(dirname "$f")"
                cp -p "$VOLUME/iPod_Control/$f" "$OUT/iPod_Control/$f"
            done
    fi
else
    echo "volume files: not copied (the iPod volume is not mounted)" >> "$OUT/info.txt"
    echo "    The iPod volume is not mounted. The device information files are not copied."
fi

# -- the ZIP file -----------------------------------------------------------------------------------

(cd "$OUT" && find . -type f ! -name MANIFEST.txt -print0 | sort -z | xargs -0 shasum -a 256 > MANIFEST.txt)
DEST="${IPOD_OUT_DIR:-$HOME/Desktop}"
ZIP="$DEST/ipod-info-$STAMP.zip"
N=2
while [ -e "$ZIP" ]; do ZIP="$DEST/ipod-info-$STAMP-$N.zip"; N=$((N + 1)); done
ditto -c -k --keepParent "$OUT" "$ZIP"

# Removes the temporary files without a recursive delete:
#  1. each file in MANIFEST.txt (the script made the list), one at a time, only if it is a regular
#     file (not a link) and its real folder is inside the real temporary folder;
#  2. each folder, deepest first, with rmdir, which removes only an empty folder.
# Anything else stays, and the script shows where it is.
remove_temp_files() {
    local out_real line rel f dir_real
    out_real="$(cd "$OUT" && pwd -P)" || return 1
    while IFS= read -r line; do
        rel="${line#*  ./}"
        case "$rel" in ""|/*|*..*) continue ;; esac
        f="$OUT/$rel"
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        dir_real="$(cd "$(dirname "$f")" && pwd -P)" || continue
        case "$dir_real" in "$out_real"|"$out_real"/*) rm -f -- "$f" ;; esac
    done < "$OUT/MANIFEST.txt"
    rm -f -- "$OUT/MANIFEST.txt"
    find "$OUT" -depth -type d -exec rmdir {} \; 2>/dev/null
    rmdir "$WORK" 2>/dev/null
}
remove_temp_files || true
[ -d "$WORK" ] && echo "    Some temporary files were not removed. They are in: $WORK"
echo
echo "==> Done. Nothing was written to the iPod."
echo "    File:   $ZIP"
echo "    Size:   $(du -h "$ZIP" | cut -f1)"
echo "    SHA-256: $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
if [ "$FIRMWARE" = 1 ]; then
    echo "    Send this file privately. It contains Apple firmware. Do not post it in public."
else
    echo "    Send this file privately."
fi
