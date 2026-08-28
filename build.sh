#!/usr/bin/env bash
#
# Packages MyLootHistory into a zip ready to upload to CurseForge.
#
# Validates the .toc, checks that every file it lists exists, copies the
# addon into dist/MyLootHistory (dev-only files excluded) and zips it as
# dist/MyLootHistory-<version>.zip. Also prints the metadata CurseForge
# asks for on the upload form (game version, changelog).
#
# Usage:
#   ./build.sh
#   ./build.sh --version 1.5.0
#   ./build.sh --clean
#
# Bash port of build.ps1 - the two produce the same package.

set -euo pipefail

ADDON_NAME='MyLootHistory'
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOC_PATH="$ROOT/$ADDON_NAME.toc"
DIST_DIR="$ROOT/dist"
STAGE_DIR="$DIST_DIR/$ADDON_NAME"

# Anything matching these is never shipped to CurseForge.
EXCLUDE_DIRS=('.git' '.vscode' '.github' 'dist' 'node_modules')
EXCLUDE_FILES=('build.ps1' 'build.cmd' 'build.sh' 'AUDIT.html' '.gitignore' '.DS_Store' '.luacheckrc')

if [ -t 1 ]; then
    RED=$'\033[31m'; GREEN=$'\033[32m'; CYAN=$'\033[36m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
    RED=''; GREEN=''; CYAN=''; YELLOW=''; RESET=''
fi

fail() { printf '%sERROR: %s%s\n' "$RED" "$1" "$RESET" >&2; exit 1; }
step() { printf '%s==> %s%s\n' "$CYAN" "$1" "$RESET"; }
warn() { printf '%s  ! %s%s\n' "$YELLOW" "$1" "$RESET"; }
ok()   { printf '%s  %s%s\n' "$GREEN" "${1:-ok}" "$RESET"; }

VERSION=''
CLEAN=0
while [ $# -gt 0 ]; do
    case "$1" in
        -v|--version|-Version)
            [ $# -ge 2 ] || fail "$1 needs a value"
            VERSION="$2"; shift 2 ;;
        -c|--clean|-Clean)
            CLEAN=1; shift ;;
        -h|--help)
            sed -n '3,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)
            fail "Unknown argument '$1'" ;;
    esac
done

[ -f "$TOC_PATH" ] || fail "$ADDON_NAME.toc not found in $ROOT"

# --- version -----------------------------------------------------------------
if [ -n "$VERSION" ]; then
    [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Version must look like 1.5.0, got '$VERSION'"
    step "Setting version to $VERSION in $ADDON_NAME.toc"
    tmp="$(mktemp)"
    sed "s/^##[[:space:]]*Version:.*$/## Version: $VERSION/" "$TOC_PATH" > "$tmp"
    cat "$tmp" > "$TOC_PATH"
    rm -f "$tmp"
fi

toc_field() {
    sed -n "s/^##[[:space:]]*$1:[[:space:]]*//p" "$TOC_PATH" | head -n 1 | tr -d '\r' \
        | sed -e 's/[[:space:]]*$//'
}

ADDON_VERSION="$(toc_field Version)"
[ -n "$ADDON_VERSION" ] || fail 'No "## Version:" line in the .toc'

INTERFACE="$(toc_field Interface)"
[ -n "$INTERFACE" ] || fail 'No "## Interface:" line in the .toc'

# 120100 -> 12.1.0
if [[ "$INTERFACE" =~ ^([0-9]+)([0-9]{2})([0-9]{2})$ ]]; then
    GAME_VERSION="$((10#${BASH_REMATCH[1]})).$((10#${BASH_REMATCH[2]})).$((10#${BASH_REMATCH[3]}))"
else
    GAME_VERSION="$INTERFACE"
    warn "Interface '$INTERFACE' is not the expected 6-digit form"
fi

step "$ADDON_NAME $ADDON_VERSION (Interface $INTERFACE / WoW $GAME_VERSION)"

# --- validate the file list --------------------------------------------------
step 'Checking files referenced by the .toc'
missing=()
while IFS= read -r line; do
    entry="$(printf '%s' "$line" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -n "$entry" ] || continue
    case "$entry" in '#'*) continue ;; esac
    entry="${entry%%[[:space:]]*}"          # strip any trailing load conditions
    path="${entry//\\//}"                   # .toc uses backslashes
    [ -f "$ROOT/$path" ] || missing+=("$entry")
done < "$TOC_PATH"
if [ ${#missing[@]} -gt 0 ]; then
    fail "$(printf 'Listed in the .toc but missing on disk:\n  %s' "$(printf '%s\n  ' "${missing[@]}")")"
fi
ok

# --- lua syntax check (optional, only if luac/luacheck is installed) ---------
find_args=()
for d in "${EXCLUDE_DIRS[@]}"; do
    find_args+=(-name "$d" -prune -o)
done
lua_files=()
while IFS= read -r f; do lua_files+=("$f"); done < <(
    find "$ROOT" "${find_args[@]}" -type f -name '*.lua' -print | sort
)

if command -v luacheck >/dev/null 2>&1; then
    step 'Running luacheck'
    luacheck "$ROOT" --no-color || warn 'luacheck reported problems (not fatal)'
elif command -v luac >/dev/null 2>&1; then
    step "Syntax-checking ${#lua_files[@]} Lua files with luac"
    bad=()
    for f in "${lua_files[@]}"; do
        luac -p "$f" || bad+=("$f")
    done
    if [ ${#bad[@]} -gt 0 ]; then
        fail "$(printf 'Lua syntax errors in:\n  %s' "$(printf '%s\n  ' "${bad[@]}")")"
    fi
    ok
else
    warn 'Neither luacheck nor luac found on PATH - skipping the Lua syntax check'
fi

# --- changelog ---------------------------------------------------------------
CHANGELOG_PATH="$ROOT/CHANGELOG.md"
CHANGELOG_BODY=''
if [ -f "$CHANGELOG_PATH" ]; then
    head_line="$(grep -m 1 -n '^## ' "$CHANGELOG_PATH" || true)"
    if [ -n "$head_line" ]; then
        start="${head_line%%:*}"
        heading="${head_line#*:}"
        case "$heading" in
            *"$ADDON_VERSION"*) ;;
            *) warn "CHANGELOG.md's newest entry is '$heading' but the .toc says $ADDON_VERSION" ;;
        esac
        CHANGELOG_BODY="$(
            awk -v start="$start" 'NR > start { if (/^## /) exit; print }' "$CHANGELOG_PATH" \
                | sed -e '/./,$!d' | awk 'NF {p = NR} {l[NR] = $0} END { for (i = 1; i <= p; i++) print l[i] }'
        )"
    fi
else
    warn 'No CHANGELOG.md'
fi

# --- stage -------------------------------------------------------------------
if [ "$CLEAN" -eq 1 ] && [ -d "$DIST_DIR" ]; then
    step 'Cleaning dist/'
    rm -rf "$DIST_DIR"
fi
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

step "Staging into dist/$ADDON_NAME"
copied=0
while IFS= read -r src; do
    rel="${src#"$ROOT"/}"
    skip=0
    for d in "${EXCLUDE_DIRS[@]}"; do
        case "$rel" in "$d"/*) skip=1; break ;; esac
    done
    [ "$skip" -eq 0 ] || continue
    base="$(basename "$rel")"
    for f in "${EXCLUDE_FILES[@]}"; do
        [ "$base" != "$f" ] || { skip=1; break; }
    done
    [ "$skip" -eq 0 ] || continue

    mkdir -p "$STAGE_DIR/$(dirname "$rel")"
    cp -p "$src" "$STAGE_DIR/$rel"
    copied=$((copied + 1))
done < <(find "$ROOT" "${find_args[@]}" -type f -print)
ok "$copied files"

# --- zip ---------------------------------------------------------------------
ZIP_PATH="$DIST_DIR/$ADDON_NAME-$ADDON_VERSION.zip"
rm -f "$ZIP_PATH"
step "Zipping $ADDON_NAME-$ADDON_VERSION.zip"
command -v zip >/dev/null 2>&1 || fail 'zip not found on PATH'
(cd "$DIST_DIR" && zip -q -r -9 -X "$ZIP_PATH" "$ADDON_NAME")

if size_kb="$(du -k "$ZIP_PATH" 2>/dev/null | cut -f1)"; then :; else size_kb='?'; fi

# --- summary -----------------------------------------------------------------
echo
printf '%sPackage:      %s (%s KB)%s\n' "$GREEN" "$ZIP_PATH" "$size_kb" "$RESET"
echo "Display name: $ADDON_NAME-$ADDON_VERSION"
echo "Release type: release"
echo "Game version: $GAME_VERSION (Retail)"
if [ -n "$CHANGELOG_BODY" ]; then
    echo
    echo '--- changelog for the upload form ---'
    printf '%s\n' "$CHANGELOG_BODY"
    echo '-------------------------------------'
fi
echo
echo 'Upload at: https://legacy.curseforge.com/wow/addons/<your-project>/upload-file'
