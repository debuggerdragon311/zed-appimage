#!/usr/bin/env bash
# build-appdir.sh — Assemble the AppDir for Zed
# Usage: bash build-appdir.sh <arch> <version_num>

set -euo pipefail

ARCH="${1:?arch required}"
VERSION="${2:?version required}"
APPDIR="AppDir"

echo "==> Building AppDir for Zed $VERSION ($ARCH)"

# ── Locate the zed.app root from the extracted tarball ───────────────────────
# Zed tarballs always extract to zed.app/
ZED_APP=$(find . -maxdepth 2 -type d -name 'zed.app' ! -path './.git/*' | head -1)
if [[ -z "$ZED_APP" ]]; then
  echo "ERROR: Could not find zed.app directory in extracted tarball." >&2
  find . -maxdepth 3 ! -path './.git/*' | sort >&2
  exit 1
fi
echo "Found zed.app at: $ZED_APP"

# ── Verify the critical binaries exist ───────────────────────────────────────
ZED_LAUNCHER="$ZED_APP/bin/zed"
ZED_EDITOR="$ZED_APP/libexec/zed-editor"

[[ -f "$ZED_LAUNCHER" ]] || { echo "ERROR: missing $ZED_LAUNCHER" >&2; exit 1; }
[[ -f "$ZED_EDITOR"   ]] || { echo "ERROR: missing $ZED_EDITOR"   >&2; exit 1; }

echo "Launcher : $ZED_LAUNCHER ($(du -sh "$ZED_LAUNCHER" | cut -f1))"
echo "Editor   : $ZED_EDITOR   ($(du -sh "$ZED_EDITOR"   | cut -f1))"

# ── Create AppDir skeleton ────────────────────────────────────────────────────
mkdir -p \
  "$APPDIR/usr/bin" \
  "$APPDIR/usr/lib" \
  "$APPDIR/usr/libexec" \
  "$APPDIR/usr/share/applications" \
  "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# ── Copy binaries ─────────────────────────────────────────────────────────────
# The real editor binary (large — this is what was missing before)
cp "$ZED_EDITOR"   "$APPDIR/usr/libexec/zed-editor"
chmod +x "$APPDIR/usr/libexec/zed-editor"

# The launcher wrapper (calls libexec/zed-editor)
cp "$ZED_LAUNCHER" "$APPDIR/usr/bin/zed"
chmod +x "$APPDIR/usr/bin/zed"

# ── Copy bundled libs ─────────────────────────────────────────────────────────
if [[ -d "$ZED_APP/lib" ]]; then
  cp -r "$ZED_APP/lib"/. "$APPDIR/usr/lib/"
  echo "Copied $(ls "$APPDIR/usr/lib" | wc -l) bundled libs"
fi

# ── Copy upstream share/ (includes icons and desktop file) ───────────────────
if [[ -d "$ZED_APP/share" ]]; then
  cp -r "$ZED_APP/share"/. "$APPDIR/usr/share/"
  echo "Copied upstream share/ tree"
fi

# ── Fix icon names and positions ──────────────────────────────────────────────
# Problem 1: Upstream ships icon as "dev.zed.Zed.png" but desktop says Icon=zed
#            → rename every icon file to zed.png so the name matches
# Problem 2: Upstream ships icon only at 1024x1024
#            → appimagetool and DE icon themes need 256x256 specifically
# Problem 3: AppImage spec requires AppDir/zed.png at the root

echo "==> Fixing icon names and sizes..."

# Rename all upstream icon files from dev.zed.Zed.* → zed.*
find "$APPDIR/usr/share/icons" -type f \( -name 'dev.zed.Zed.*' -o -name 'zed-editor.*' \) | \
while read -r f; do
  EXT="${f##*.}"
  DIR="$(dirname "$f")"
  mv "$f" "$DIR/zed.$EXT"
  echo "  Renamed: $f → $DIR/zed.$EXT"
done

# Find the best source icon (largest png available after rename)
SOURCE_ICON=$(find "$APPDIR/usr/share/icons" -name 'zed.png' \
  | awk -F/ '{print NF, $0}' | sort -rn | head -1 | cut -d' ' -f2- || true)

if [[ -z "$SOURCE_ICON" ]]; then
  # Nothing in share/icons at all — generate a fallback
  echo "  No upstream icon found, generating fallback..."
  SOURCE_ICON="/tmp/zed-icon-fallback.png"
  convert -size 1024x1024 xc:'#084CCF' \
    -fill white -font DejaVu-Sans-Bold -pointsize 500 \
    -gravity Center -annotate 0 'Z' "$SOURCE_ICON"
fi

echo "  Source icon: $SOURCE_ICON ($(du -sh "$SOURCE_ICON" | cut -f1))"

# Ensure 256x256 exists — this is what appimagetool looks for
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
ICON_256="$APPDIR/usr/share/icons/hicolor/256x256/apps/zed.png"
if [[ ! -f "$ICON_256" ]]; then
  convert "$SOURCE_ICON" -resize 256x256 "$ICON_256"
  echo "  Created 256x256 icon"
fi

# Ensure 512x512 exists (nice to have for HiDPI desktops)
mkdir -p "$APPDIR/usr/share/icons/hicolor/512x512/apps"
ICON_512="$APPDIR/usr/share/icons/hicolor/512x512/apps/zed.png"
if [[ ! -f "$ICON_512" ]]; then
  convert "$SOURCE_ICON" -resize 512x512 "$ICON_512"
  echo "  Created 512x512 icon"
fi

# AppImage spec: root-level icon must match Icon= name in desktop file (Icon=zed → zed.png)
# appimagetool also creates a .DirIcon symlink from this
cp "$ICON_256" "$APPDIR/zed.png"
echo "  Placed root zed.png (AppImage spec + .DirIcon source)"

echo "==> Icon tree:"
find "$APPDIR/usr/share/icons" -type f | sort

# ── Desktop entry ─────────────────────────────────────────────────────────────
# Use upstream desktop file if present, otherwise create one
UPSTREAM_DESKTOP=$(find "$APPDIR/usr/share/applications" -name '*.desktop' | head -1 || true)

if [[ -n "$UPSTREAM_DESKTOP" ]]; then
  echo "Using upstream desktop file: $UPSTREAM_DESKTOP"
  # AppImage spec: must have Icon=zed (no path, no extension) and Exec=zed
  sed -i \
    -e 's|^Icon=.*|Icon=zed|' \
    -e 's|^Exec=.*|Exec=zed %F|' \
    "$UPSTREAM_DESKTOP"
  cp "$UPSTREAM_DESKTOP" "$APPDIR/zed.desktop"
else
  echo "Creating desktop file..."
  cat > "$APPDIR/usr/share/applications/zed.desktop" << DESKTOP
[Desktop Entry]
Name=Zed
GenericName=Text Editor
Comment=A high-performance, multiplayer code editor
Exec=zed %F
Icon=zed
Type=Application
Categories=Development;TextEditor;IDE;Utility;
MimeType=text/plain;inode/directory;
Keywords=editor;code;text;rust;
StartupWMClass=zed
X-AppImage-Version=$VERSION
DESKTOP
  cp "$APPDIR/usr/share/applications/zed.desktop" "$APPDIR/zed.desktop"
fi

desktop-file-validate "$APPDIR/zed.desktop"
echo "Desktop file valid ✓"

# ── AppRun entrypoint ─────────────────────────────────────────────────────────
# Critical: set LIBEXEC path so bin/zed wrapper finds zed-editor
cat > "$APPDIR/AppRun" << 'APPRUN'
#!/bin/bash
SELF_DIR="$(dirname "$(readlink -f "$0")")"

export PATH="$SELF_DIR/usr/bin:$PATH"

# libexec must be discoverable so the bin/zed wrapper can exec zed-editor
export ZED_LIBEXEC_PATH="$SELF_DIR/usr/libexec"

# Prepend bundled libs
if [[ -d "$SELF_DIR/usr/lib" ]]; then
  export LD_LIBRARY_PATH="$SELF_DIR/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

# Try the launcher wrapper first; fall back directly to the editor binary
if [[ -x "$SELF_DIR/usr/bin/zed" ]]; then
  exec "$SELF_DIR/usr/bin/zed" "$@"
else
  exec "$SELF_DIR/usr/libexec/zed-editor" "$@"
fi
APPRUN
chmod +x "$APPDIR/AppRun"

# ── Size check ────────────────────────────────────────────────────────────────
echo ""
echo "==> AppDir sizes:"
du -sh "$APPDIR/usr/bin/zed"
du -sh "$APPDIR/usr/libexec/zed-editor"
du -sh "$APPDIR/usr/lib"
du -sh "$APPDIR"
echo ""
echo "==> AppDir layout (top-level):"
find "$APPDIR" -maxdepth 3 -not -path '*/\.*' | sort
echo ""
echo "==> AppDir ready ✓"
