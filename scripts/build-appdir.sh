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

# ── Ensure a 256x256 icon exists (AppImage spec needs one at root) ────────────
# Prefer the upstream icon; fall back to any png we can find; then generate one
ICON_DEST="$APPDIR/usr/share/icons/hicolor/256x256/apps/zed.png"

if [[ ! -f "$ICON_DEST" ]]; then
  # Search for any png icon in the copied share tree
  FOUND=$(find "$APPDIR/usr/share/icons" -name '*.png' | head -1 || true)
  if [[ -n "$FOUND" ]]; then
    convert "$FOUND" -resize 256x256 "$ICON_DEST" 2>/dev/null || cp "$FOUND" "$ICON_DEST"
  else
    echo "Generating fallback icon..."
    convert -size 256x256 xc:'#084CCF' \
      -fill white -font DejaVu-Sans-Bold -pointsize 120 \
      -gravity Center -annotate 0 'Z' "$ICON_DEST"
  fi
fi
cp "$ICON_DEST" "$APPDIR/zed.png"

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
