#!/bin/bash
# Build iPodFirm.app and install it into /Applications.
# Every run increments BOTH the version (patch) and the build number in version.env.
set -euo pipefail
cd "$(dirname "$0")/.."

source version.env
if [ "$BUILD_NUMBER" -gt 0 ]; then
    IFS=. read -r MAJOR MINOR PATCH <<< "$MARKETING_VERSION"
    MARKETING_VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
fi
BUILD_NUMBER=$((BUILD_NUMBER + 1))
echo "==> Building iPodFirm $MARKETING_VERSION ($BUILD_NUMBER)"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)"

APP=build/iPodFirm.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/iPodFirm" "$BIN/ipodfw-helper" "$APP/Contents/MacOS/"
mkdir -p "$APP/Contents/Library/LaunchDaemons"
cp Resources/com.thefauxdreamer.ipodfirm.helper.plist "$APP/Contents/Library/LaunchDaemons/"
cp Resources/install-emulator.sh "$APP/Contents/Resources/"

if [ ! -f build/AppIcon.icns ]; then
    swift scripts/make-icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>iPodFirm</string>
    <key>CFBundleDisplayName</key><string>iPodFirm</string>
    <key>CFBundleIdentifier</key><string>com.thefauxdreamer.ipodfirm</string>
    <key>CFBundleExecutable</key><string>iPodFirm</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$MARKETING_VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>GPL-2.0-or-later. Formats from iPodWizard and Rockbox ipodpatcher.</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSExceptionDomains</key>
        <dict>
            <key>appldnld.apple.com.edgesuite.net</key>
            <dict><key>NSExceptionAllowsInsecureHTTPLoads</key><true/></dict>
        </dict>
    </dict>
</dict>
</plist>
PLIST

# Sign with a stable identity so macOS keeps Full Disk Access across rebuilds
# (an ad-hoc signature changes every build and silently loses the permission).
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
if [ -z "$IDENTITY" ]; then
    echo "warning: no signing identity found; ad-hoc signing (Full Disk Access must be re-granted after each build)"
    IDENTITY="-"
fi
codesign --force --sign "$IDENTITY" --identifier com.thefauxdreamer.ipodfirm.helper "$APP/Contents/MacOS/ipodfw-helper"
codesign --force --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

# Only record the new numbers once the build has succeeded.
printf 'MARKETING_VERSION=%s\nBUILD_NUMBER=%s\n' "$MARKETING_VERSION" "$BUILD_NUMBER" > version.env

if [ -d /Applications/iPodFirm.app ]; then
    osascript -e 'tell application "iPodFirm" to quit' >/dev/null 2>&1 || true
    rm -rf /Applications/iPodFirm.app
fi
ditto "$APP" /Applications/iPodFirm.app
echo "==> Installed /Applications/iPodFirm.app — version $MARKETING_VERSION (build $BUILD_NUMBER)"
