#!/bin/bash
# Build and safely install macSteam Private. Existing private installs are moved
# to a timestamped backup and can be restored with --restore-latest.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
DESTINATION="${MACSTEAM_PRIVATE_INSTALL_DIR:-/Applications}"
BACKUP_ROOT="${MACSTEAM_PRIVATE_BACKUP_DIR:-$HOME/Library/Application Support/macSteam Private/Install Backups}"
APP_NAME="macSteam Private.app"
BUNDLE_ID="com.weibao.macsteam.private"
MODE="install"

usage() {
    echo "usage: $0 [--build-only | --restore-latest] [--destination DIR]"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --build-only)
            MODE="build-only"
            shift
            ;;
        --restore-latest)
            MODE="restore"
            shift
            ;;
        --destination)
            if [ "$#" -lt 2 ]; then
                usage >&2
                exit 64
            fi
            DESTINATION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 64
            ;;
    esac
done

TARGET="$DESTINATION/$APP_NAME"

bundle_id() {
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null
}

verify_private_app() {
    candidate="$1"
    if [ ! -d "$candidate" ]; then
        echo "error: app bundle not found: $candidate" >&2
        return 1
    fi
    if [ "$(bundle_id "$candidate")" != "$BUNDLE_ID" ]; then
        echo "error: refusing app with unexpected bundle identifier: $candidate" >&2
        return 1
    fi
    if [ "$(/usr/libexec/PlistBuddy -c 'Print :MacSteamBuildFlavor' "$candidate/Contents/Info.plist" 2>/dev/null)" != "private" ]; then
        echo "error: refusing app without private build metadata: $candidate" >&2
        return 1
    fi
    if [ "$(/usr/libexec/PlistBuddy -c 'Print :MacSteamUpdatesEnabled' "$candidate/Contents/Info.plist" 2>/dev/null)" != "false" ]; then
        echo "error: refusing private app without disabled-update metadata" >&2
        return 1
    fi
    if /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$candidate/Contents/Info.plist" >/dev/null 2>&1 || \
       /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$candidate/Contents/Info.plist" >/dev/null 2>&1; then
        echo "error: refusing private app that contains upstream Sparkle metadata" >&2
        return 1
    fi
    codesign --verify --deep --strict "$candidate"
}

if [ "$MODE" = "restore" ]; then
    if [ ! -d "$BACKUP_ROOT" ]; then
        echo "error: no private install backups found" >&2
        exit 1
    fi
    LATEST=$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name '*.app' -print | sort | tail -1)
    if [ -z "$LATEST" ]; then
        echo "error: no private install backups found" >&2
        exit 1
    fi
    mkdir -p "$DESTINATION"
    RESTORE_STAGING=$(mktemp -d "$DESTINATION/.macsteam-private-restore.XXXXXX")
    RESTORE_APP="$RESTORE_STAGING/$APP_NAME"
    restore_cleanup() {
        if [ -d "$RESTORE_STAGING" ]; then
            rm -rf "$RESTORE_STAGING"
        fi
    }
    trap restore_cleanup EXIT
    ditto "$LATEST" "$RESTORE_APP"
    verify_private_app "$RESTORE_APP"
    if [ -e "$TARGET" ]; then
        if [ "$(bundle_id "$TARGET")" != "$BUNDLE_ID" ]; then
            echo "error: refusing to replace non-private app at $TARGET" >&2
            exit 1
        fi
        mkdir -p "$BACKUP_ROOT"
        ROLLBACK="$BACKUP_ROOT/$(date -u '+%Y%m%dT%H%M%SZ')-pre-restore-$$.app"
        mv "$TARGET" "$ROLLBACK"
        echo "Moved current install to $ROLLBACK"
    fi
    mv "$RESTORE_APP" "$TARGET"
    verify_private_app "$TARGET"
    echo "Restored $TARGET (backup retained at $LATEST)"
    exit 0
fi

make -C "$REPO_DIR"
MACSTEAM_BUILD_FLAVOR=private "$SCRIPT_DIR/make_app.sh"
BUILT_APP="$SCRIPT_DIR/$APP_NAME"
verify_private_app "$BUILT_APP"

if [ "$MODE" = "build-only" ]; then
    echo "Verified private build: $BUILT_APP"
    exit 0
fi

mkdir -p "$DESTINATION"
STAGING=$(mktemp -d "$DESTINATION/.macsteam-private-install.XXXXXX")
STAGED_APP="$STAGING/$APP_NAME"
PREVIOUS_BACKUP=""
INSTALL_COMPLETE="false"
cleanup() {
    if [ "$INSTALL_COMPLETE" != "true" ] && [ -n "$PREVIOUS_BACKUP" ] && [ -d "$PREVIOUS_BACKUP" ]; then
        if [ -e "$TARGET" ]; then
            FAILED_COPY="$BACKUP_ROOT/$(date -u '+%Y%m%dT%H%M%SZ')-failed-$$.app"
            mv "$TARGET" "$FAILED_COPY"
            echo "Preserved failed install at $FAILED_COPY" >&2
        fi
        mv "$PREVIOUS_BACKUP" "$TARGET"
        echo "Restored previous install after failure" >&2
    fi
    if [ -d "$STAGING" ]; then
        rm -rf "$STAGING"
    fi
}
trap cleanup EXIT

ditto "$BUILT_APP" "$STAGED_APP"
verify_private_app "$STAGED_APP"

if [ -e "$TARGET" ]; then
    if [ "$(bundle_id "$TARGET")" != "$BUNDLE_ID" ]; then
        echo "error: refusing to replace non-private app at $TARGET" >&2
        exit 1
    fi
    mkdir -p "$BACKUP_ROOT"
    BACKUP="$BACKUP_ROOT/$(date -u '+%Y%m%dT%H%M%SZ')-$$.app"
    mv "$TARGET" "$BACKUP"
    PREVIOUS_BACKUP="$BACKUP"
    echo "Moved previous install to $BACKUP"
fi

mv "$STAGED_APP" "$TARGET"
verify_private_app "$TARGET"
INSTALL_COMPLETE="true"
echo "Installed $TARGET"
