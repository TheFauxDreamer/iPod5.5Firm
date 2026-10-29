#!/bin/zsh
# usage: nav.sh NAME [ENV=VAL ...]  -> boot, pick English, open Music > Playlists, shot pl.png
name=$1; shift
[[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "bad NAME"; exit 1; }
W=${PF_WORK:-/tmp/pf-work}; cd "$W" || exit 1; H=${0:A:h}
[ -f $name/pid ] && kill $(cat $name/pid) 2>/dev/null; pkill -f "ipod-emulator --headless"; sleep 1
rm -rf $name/profile/cache/snapshots; mkdir -p $name/shots
$H/srv.sh $name "$@"; sleep 3; $H/w.sh 35
for k in 1 2 3; do $H/c.sh "press select" >/dev/null; $H/w.sh 4; done
$H/c.sh "shot $W/$name/shots/pl.png" >/dev/null
