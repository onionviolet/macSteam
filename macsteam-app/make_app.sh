#!/bin/bash
# Build MacsteamApp and package it as a private build by default, ad-hoc signed.
# Set MACSTEAM_BUILD_FLAVOR=upstream to reproduce the public/upstream identity.
set -euo pipefail

cd "$(dirname "$0")"

BIN_NAME="MacsteamApp"
ICON_SRC="AppIcon.icns"
BUILD_FLAVOR="${MACSTEAM_BUILD_FLAVOR:-private}"

case "$BUILD_FLAVOR" in
    private)
        APP="macSteam Private.app"
        DISPLAY_NAME="macSteam Private"
        BUNDLE_ID="com.weibao.macsteam.private"
        UPDATES_ENABLED="false"
        ;;
    upstream)
        APP="macSteam Config.app"
        DISPLAY_NAME="macSteam Config"
        BUNDLE_ID="com.macsteam.app"
        UPDATES_ENABLED="true"
        ;;
    *)
        echo "error: MACSTEAM_BUILD_FLAVOR must be 'private' or 'upstream'" >&2
        exit 64
        ;;
esac

if [ ! -f "$ICON_SRC" ]; then
    swift make_icon.swift
fi

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Frameworks"
mkdir -p "$APP/Contents/Resources/ThirdPartyLicenses"

cp ".build/release/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/$BIN_NAME"
cp "$ICON_SRC" "$APP/Contents/Resources/AppIcon.icns"

# Built by the top-level Makefile (make rebuild).
DYLIB_SRC="../out/macsteam.dylib"
MS_VERSION=$(sed -n 's/.*MACSTEAM_VERSION[[:space:]]*"\(.*\)".*/\1/p' ../src/version.h)
if [ -z "$MS_VERSION" ]; then
    echo "error: could not read MACSTEAM_VERSION from ../src/version.h" >&2
    exit 1
fi

SOURCE_REVISION=$(git -C .. rev-parse --short=12 HEAD 2>/dev/null || printf 'unknown')
SOURCE_BRANCH=$(git -C .. branch --show-current 2>/dev/null || true)
if [ -z "$SOURCE_BRANCH" ]; then
    SOURCE_BRANCH="detached"
fi
if [ -n "$(git -C .. status --porcelain 2>/dev/null || true)" ]; then
    SOURCE_DIRTY="true"
    DIRTY_SUFFIX="-dirty"
else
    SOURCE_DIRTY="false"
    DIRTY_SUFFIX=""
fi
BUILD_NUMBER=$(git -C .. rev-list --count HEAD 2>/dev/null || printf '1')
BUILT_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
BUILD_LABEL="$MS_VERSION-$BUILD_FLAVOR.$SOURCE_REVISION$DIRTY_SUFFIX"
if [ -f "$DYLIB_SRC" ]; then
    cp "$DYLIB_SRC" "$APP/Contents/Resources/macsteam.dylib"
    printf '%s' "$MS_VERSION" > "$APP/Contents/Resources/macsteam.dylib.version"
else
    echo "warning: $DYLIB_SRC missing -- Install pane will report no payload" >&2
fi

SIG_SRC="../signatures"
if [ -d "$SIG_SRC" ]; then
    cp -R "$SIG_SRC" "$APP/Contents/Resources/signatures"
else
    echo "warning: $SIG_SRC missing -- hooks won't resolve without signatures" >&2
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$DISPLAY_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>      <string>$BIN_NAME</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$MS_VERSION</string>
    <key>CFBundleVersion</key>         <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key> <string>© 2026 Selectively11</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>MacSteamBuildFlavor</key>     <string>$BUILD_FLAVOR</string>
    <key>MacSteamUpdatesEnabled</key>  <$UPDATES_ENABLED/>
</dict>
</plist>
PLIST

# PlistBuddy handles XML escaping for revision metadata that originates in Git.
/usr/libexec/PlistBuddy -c "Add :MacSteamSourceRevision string $SOURCE_REVISION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :MacSteamSourceBranch string $SOURCE_BRANCH" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :MacSteamSourceDirty bool $SOURCE_DIRTY" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :MacSteamBuiltAt string $BUILT_AT" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :MacSteamBuildLabel string $BUILD_LABEL" "$APP/Contents/Info.plist"

if [ "$BUILD_FLAVOR" = "upstream" ]; then
    /usr/libexec/PlistBuddy -c \
        "Add :SUFeedURL string https://raw.githubusercontent.com/Selectively11/macsteam/main/appcast.xml" \
        "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c \
        "Add :SUPublicEDKey string rDOXzJ+vt12aWeu9hATgvz6q46MlRcgR4gbTfj5YuWQ=" \
        "$APP/Contents/Info.plist"
fi

SPARKLE_FW=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
    cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
    cp ".build/checkouts/Sparkle/LICENSE" "$APP/Contents/Resources/ThirdPartyLicenses/Sparkle.LICENSE"
else
    echo "warning: Sparkle.framework not found -- auto-update disabled at runtime" >&2
fi

echo "APPL????" > "$APP/Contents/PkgInfo"

touch "$APP"

codesign -fs - "$APP"

echo "Built $APP ($BUILD_LABEL, bundle build $BUILD_NUMBER)"
codesign -dv "$APP" 2>&1 | head -3 || true
