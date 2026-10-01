#!/bin/bash
# Installs or updates siggifly/ipod-emulator from source into /Applications/ipod-emulator.app.
# Run by iPodFirm (Emulator pane). Rust is installed into ~/.rustup and ~/.cargo if missing
# (remove later with `~/.cargo/bin/rustup self uninstall`).
set -euo pipefail

SRC="$HOME/Library/Application Support/iPodFirm/emulator-src"
CARGO="$HOME/.cargo/bin/cargo"
REPO="https://github.com/siggifly/ipod-emulator.git"

if [ ! -x "$CARGO" ]; then
    echo "==> Installing Rust into your home folder (rustup)…"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal
fi

if [ -d "$SRC/.git" ]; then
    echo "==> Updating emulator source…"
    git -C "$SRC" pull --ff-only
else
    echo "==> Downloading emulator source…"
    mkdir -p "$(dirname "$SRC")"
    git clone "$REPO" "$SRC"
fi
cd "$SRC"
echo "==> Source at $(git log -1 --format='%h (%cd)' --date=short)"

echo "==> Compiling (this takes a few minutes the first time)…"
"$CARGO" build --release -p ipod-gui -p ipod-machine

echo "==> Building the app bundle…"
OUT="$(mktemp -d)"
ICON=""
for c in resources/icon.png docs/media/icon.png docs/media/ipod-30-synthetic-nor-boot.png; do
    if [ -f "$c" ]; then ICON="$c"; break; fi
done
./target/release/ipod-emulator --make-app "$OUT" ${ICON:+"$ICON"}

rm -rf /Applications/ipod-emulator.app
ditto "$OUT/ipod-emulator.app" /Applications/ipod-emulator.app
rm -rf "$OUT"
echo "==> Installed /Applications/ipod-emulator.app"
