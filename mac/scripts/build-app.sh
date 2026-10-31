#!/bin/bash
# Build iPodFirm.app and install it into /Applications.
# Every run increments BOTH the version (patch) and the build number in version.env.
# Set APP_NAME to install a second copy with a different name, for example a test build:
#   APP_NAME="iPodFirm USB-C Test" mac/scripts/build-app.sh
# Set RELEASE=1 to make a ZIP file for a GitHub release. A release build has an ad-hoc
# signature, which contains no name and no e-mail address. The script does not install it.
# Set RELEASE=both to make the release ZIP and install the app from the same build. The two
# copies have the same version. The installed copy keeps the signature of a normal build.
# On the main branch, the default is RELEASE=both. On other branches, the default is RELEASE=0.
# Set RELEASE=0 or RELEASE=1 to change the default.
set -euo pipefail
cd "$(dirname "$0")/.."
APP_NAME="${APP_NAME:-iPodFirm}"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ "$BRANCH" = main ]; then RELEASE="${RELEASE:-both}"; else RELEASE="${RELEASE:-0}"; fi
case "$RELEASE" in
    0|1|both) ;;
    *) echo "error: RELEASE must be 0, 1 or both: $RELEASE" >&2; exit 1 ;;
esac
case "$APP_NAME" in
    */*|.*|*..*) echo "error: APP_NAME must be a plain name, not a path: $APP_NAME" >&2; exit 1 ;;
esac

source version.env
if [ "$BUILD_NUMBER" -gt 0 ]; then
    IFS=. read -r MAJOR MINOR PATCH <<< "$MARKETING_VERSION"
    MARKETING_VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
fi
BUILD_NUMBER=$((BUILD_NUMBER + 1))
echo "==> Building iPodFirm $MARKETING_VERSION ($BUILD_NUMBER)"

# The compiler writes the path of each source file into the program. The option
# -file-prefix-map writes "." in place of the project folder. Thus the build does not
# change with the location of the project folder.
ROOT="$(cd .. && pwd)"
SWIFT_FLAGS=(-c release --arch arm64 -Xswiftc -file-prefix-map -Xswiftc "$ROOT=.")
swift build "${SWIFT_FLAGS[@]}"
BIN="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/iPodFirm" "$BIN/ipodfw-helper" "$APP/Contents/MacOS/"
# "strip -S" removes the debug map of the linker. The app does not use it. The function
# names stay for crash reports.
strip -S "$APP/Contents/MacOS/iPodFirm" "$APP/Contents/MacOS/ipodfw-helper"
mkdir -p "$APP/Contents/Library/LaunchDaemons"
cp Resources/com.thefauxdreamer.ipodfirm.helper.plist "$APP/Contents/Library/LaunchDaemons/"
cp Resources/install-emulator.sh "$APP/Contents/Resources/"
cp -R Resources/emulator-patches "$APP/Contents/Resources/"
# The built-in themes. Format 2 holds no byte of the Apple firmware, so the app
# can ship them (refer to re/dark-theme.md).
mkdir -p "$APP/Contents/Resources/Themes"
for t in ../themes/*.ipodtheme; do
    [ -e "$t" ] && cp "$t" "$APP/Contents/Resources/Themes/"
done
mkdir -p "$APP/Contents/Resources/Layouts"
cp ../themes/layouts/*.ipodtheme "$APP/Contents/Resources/Layouts/"
mkdir -p "$APP/Contents/Resources/patches"
for p in ../patches/*/; do
    n=$(basename "$p")
    mkdir -p "$APP/Contents/Resources/patches/$n"
    cp "$p"patch.json "$APP/Contents/Resources/patches/$n/"
    for c in "$p"*.c; do [ -e "$c" ] && cp "$c" "$APP/Contents/Resources/patches/$n/"; done   # a data patch has no C file
done

cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
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
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>com.thefauxdreamer.ipodfirm.patch</string>
            <key>UTTypeDescription</key><string>iPodFirm Patch</string>
            <key>UTTypeConformsTo</key><array><string>public.zip-archive</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>ipodpatch</string></array></dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key><string>com.thefauxdreamer.ipodfirm.eq</string>
            <key>UTTypeDescription</key><string>iPodFirm Custom EQ</string>
            <key>UTTypeConformsTo</key><array><string>public.json</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>ipodeq</string></array></dict>
        </dict>
    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>iPodFirm Patch</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Owner</string>
            <key>LSItemContentTypes</key><array><string>com.thefauxdreamer.ipodfirm.patch</string></array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key><string>iPodFirm Custom EQ</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Owner</string>
            <key>LSItemContentTypes</key><array><string>com.thefauxdreamer.ipodfirm.eq</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

sign_app() {    # $1 = the app, $2 = the identity
    # The hardened runtime stops the injection of code into the app and into the helper.
    codesign --force --options runtime --sign "$2" --identifier com.thefauxdreamer.ipodfirm.helper "$1/Contents/MacOS/ipodfw-helper"
    codesign --force --options runtime --sign "$2" "$1"
    codesign --verify --strict "$1"
}

check_private() {    # $1 = the app for the release ZIP
    # Stop if a file in the app contains a path of the build Mac or the Git e-mail address.
    local email patterns=(-e '/Users/' -e "$ROOT" -e "$HOME")
    email="$(git config user.email || true)"
    case "$email" in ""|*@users.noreply.github.com) ;; *) patterns+=(-e "$email") ;; esac
    if grep -rlaF "${patterns[@]}" "$1"; then
        echo "error: the files above contain a path of the build Mac or the Git e-mail address" >&2
        exit 1
    fi
}

make_zip() {    # $1 = the app with an ad-hoc signature
    # Stop if the signature contains a certificate (a name or an e-mail address).
    if codesign -dvv "$1" 2>&1 | grep -q '^Authority='; then
        echo "error: the release build has a certificate signature" >&2
        exit 1
    fi
    ZIP="build/$APP_NAME-$MARKETING_VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$1" "$ZIP"
    echo "==> Made $ZIP — version $MARKETING_VERSION (build $BUILD_NUMBER), ad-hoc signature"
}

# RELEASE=both: copy the unsigned app before the signature. The copy gets the ad-hoc signature.
# The path is below build/ and APP_NAME is a plain name (examined above).
RELEASE_APP="build/release/$APP_NAME.app"
if [ "$RELEASE" = both ]; then
    rm -rf "$RELEASE_APP"
    mkdir -p build/release
    ditto "$APP" "$RELEASE_APP"
fi

# Sign with a stable identity so macOS keeps Full Disk Access across rebuilds
# (an ad-hoc signature changes every build and silently loses the permission).
if [ "$RELEASE" = 1 ]; then
    # The certificate name of a developer identity contains the e-mail address or the name of the owner.
    IDENTITY="-"
else
    IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
fi
if [ -z "$IDENTITY" ]; then
    echo "warning: no signing identity found; ad-hoc signing (Full Disk Access must be re-granted after each build)"
    IDENTITY="-"
fi
sign_app "$APP" "$IDENTITY"
if [ "$RELEASE" = both ]; then sign_app "$RELEASE_APP" "-"; fi

if [ "$RELEASE" = 1 ]; then check_private "$APP"; fi
if [ "$RELEASE" = both ]; then check_private "$RELEASE_APP"; fi

# Only record the new numbers once the build has succeeded.
printf 'MARKETING_VERSION=%s\nBUILD_NUMBER=%s\n' "$MARKETING_VERSION" "$BUILD_NUMBER" > version.env

if [ "$RELEASE" = 1 ]; then
    make_zip "$APP"
    exit 0
fi
if [ "$RELEASE" = both ]; then make_zip "$RELEASE_APP"; fi

DEST="/Applications/$APP_NAME.app"
if [ -d "$DEST" ]; then
    osascript -e "tell application \"$DEST\" to quit" >/dev/null 2>&1 || true
    rm -rf "$DEST"
fi
ditto "$APP" "$DEST"
echo "==> Installed $DEST — version $MARKETING_VERSION (build $BUILD_NUMBER)"
