#!/bin/zsh
# usage: srv.sh NAME [ENV=VAL ...]  -> starts the emulator for $PF_WORK/NAME/profile on /tmp/pf-UID.sock
name=$1; shift
[[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "bad NAME"; exit 1; }
W=${PF_WORK:-/tmp/pf-work}; cd "$W" || exit 1; H=${0:A:h}
S=/tmp/pf-$(id -u).sock
[ -S $S ] && rm $S
env IPOD_EMULATOR_DATA="$W/$name/profile" IPODFW_RESET_AFTER=1000000000 "$@" \
  "$HOME/Library/Application Support/iPodFirm/emulator-src/target/release/ipod-emulator" \
  --headless=100000000000000 --control=$S >/dev/null 2>&1 &
echo $! > $name/pid
