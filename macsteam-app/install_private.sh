#!/bin/bash
# Build and safely install macSteam Private. Existing private installs are
# archived so macOS does not register rollback copies as runnable apps.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
DESTINATION="${MACSTEAM_PRIVATE_INSTALL_DIR:-/Applications}"
BACKUP_ROOT="${MACSTEAM_PRIVATE_BACKUP_DIR:-$HOME/Library/Application Support/macSteam Private/Install Backups}"
BACKUPS_TO_KEEP="${MACSTEAM_PRIVATE_BACKUPS_TO_KEEP:-3}"
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

extract_backup() {
    local archive="$1"
    local destination="$2"
    local extracted_count
    local extracted_app
    mkdir -p "$destination"
    ditto -x -k "$archive" "$destination"
    extracted_count=$(find "$destination" -mindepth 1 -maxdepth 1 -type d -name '*.app' -print | wc -l | tr -d ' ')
    if [ "$extracted_count" != "1" ]; then
        echo "error: backup must contain exactly one app bundle: $archive" >&2
        return 1
    fi
    extracted_app=$(find "$destination" -mindepth 1 -maxdepth 1 -type d -name '*.app' -print | head -1)
    if [ "$extracted_app" != "$destination/$APP_NAME" ]; then
        mv "$extracted_app" "$destination/$APP_NAME"
    fi
}

verify_backup() {
    local archive="$1"
    local verify_dir
    verify_dir=$(mktemp -d "$BACKUP_ROOT/.verify.XXXXXX")
    if ! extract_backup "$archive" "$verify_dir" || ! verify_private_app "$verify_dir/$APP_NAME"; then
        rm -rf "$verify_dir"
        return 1
    fi
    rm -rf "$verify_dir"
}

archive_app() {
    local source_app="$1"
    local archive="$2"
    local temporary_archive="$archive.tmp.$$"
    ditto -c -k --sequesterRsrc --keepParent "$source_app" "$temporary_archive"
    if ! verify_backup "$temporary_archive"; then
        rm -f "$temporary_archive"
        return 1
    fi
    mv "$temporary_archive" "$archive"
}

prune_backups() {
    case "$BACKUPS_TO_KEEP" in
        ''|*[!0-9]*|0)
            echo "error: MACSTEAM_PRIVATE_BACKUPS_TO_KEEP must be a positive integer" >&2
            return 1
            ;;
    esac
    find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type f -name '*.zip' -print | \
        sort -r | awk -v keep="$BACKUPS_TO_KEEP" 'NR > keep' | while IFS= read -r old_backup; do
            rm -f "$old_backup"
        done
}

migrate_legacy_backups() {
    local legacy_app
    local legacy_archive
    [ -d "$BACKUP_ROOT" ] || return 0
    for legacy_app in "$BACKUP_ROOT"/*.app; do
        [ -d "$legacy_app" ] || continue
        legacy_archive="${legacy_app%.app}.zip"
        archive_app "$legacy_app" "$legacy_archive"
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
            -u "$legacy_app" >/dev/null 2>&1 || true
        rm -rf "$legacy_app"
    done
    prune_backups
}

if [ "$MODE" = "restore" ]; then
    if [ ! -d "$BACKUP_ROOT" ]; then
        echo "error: no private install backups found" >&2
        exit 1
    fi
    migrate_legacy_backups
    LATEST=$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type f -name '*.zip' -print | sort | tail -1)
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
    extract_backup "$LATEST" "$RESTORE_STAGING"
    verify_private_app "$RESTORE_APP"
    if [ -e "$TARGET" ]; then
        if [ "$(bundle_id "$TARGET")" != "$BUNDLE_ID" ]; then
            echo "error: refusing to replace non-private app at $TARGET" >&2
            exit 1
        fi
        mkdir -p "$BACKUP_ROOT"
        ROLLBACK="$BACKUP_ROOT/$(date -u '+%Y%m%dT%H%M%SZ')-pre-restore-$$.zip"
        archive_app "$TARGET" "$ROLLBACK"
        rm -rf "$TARGET"
        echo "Archived current install at $ROLLBACK"
    fi
    mv "$RESTORE_APP" "$TARGET"
    verify_private_app "$TARGET"
    prune_backups
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

mkdir -p "$BACKUP_ROOT"
migrate_legacy_backups
mkdir -p "$DESTINATION"
STAGING=$(mktemp -d "$DESTINATION/.macsteam-private-install.XXXXXX")
STAGED_APP="$STAGING/$APP_NAME"
PREVIOUS_BACKUP=""
INSTALL_COMPLETE="false"
cleanup() {
    if [ "$INSTALL_COMPLETE" != "true" ] && [ -n "$PREVIOUS_BACKUP" ] && [ -f "$PREVIOUS_BACKUP" ]; then
        if [ -e "$TARGET" ]; then
            FAILED_COPY="$BACKUP_ROOT/$(date -u '+%Y%m%dT%H%M%SZ')-failed-$$.zip"
            archive_app "$TARGET" "$FAILED_COPY"
            rm -rf "$TARGET"
            echo "Preserved failed install at $FAILED_COPY" >&2
        fi
        extract_backup "$PREVIOUS_BACKUP" "$DESTINATION"
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
    BACKUP="$BACKUP_ROOT/$(date -u '+%Y%m%dT%H%M%SZ')-$$.zip"
    archive_app "$TARGET" "$BACKUP"
    rm -rf "$TARGET"
    PREVIOUS_BACKUP="$BACKUP"
    echo "Archived previous install at $BACKUP"
fi

mv "$STAGED_APP" "$TARGET"
verify_private_app "$TARGET"
INSTALL_COMPLETE="true"
prune_backups
echo "Installed $TARGET"
