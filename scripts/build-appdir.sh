#!/usr/bin/env bash
# build-appdir.sh — Assemble the AppDir for Zed
# Usage: bash build-appdir.sh <arch> <version_num>

set -euo pipefail

ARCH="${1:?arch required}"
VERSION="${2:?version required}"
APPDIR="AppDir"

echo "==> Building AppDir for Zed $VERSION ($ARCH)"

# ── Find the Zed binary (handles all known tarball layouts) ──────────────────
# Layout A (current):  zed.app/bin/zed  + zed.app/lib/...
# Layout B (older):    zed/zed  or  ./zed
ZED_BIN=$(find . -maxdepth 5 -type f -name 'zed' \
  ! -path './.git/*' ! -path './AppDir/*' | head -1)

if [[ -z "$ZED_BIN" ]]; then
  echo "ERROR: Could not find 'zed' binary in extracted tarball." >&2
  echo "Contents:" >&2
  find . -maxdepth 4 ! -path './.git/*' | sort >&2
  exit 1
fi
echo "Found Zed binary: $ZED_BIN"

ZED_BIN_DIR=$(dirname "$ZED_BIN")

# ── Create AppDir skeleton ────────────────────────────────────────────────────
mkdir -p \
  "$APPDIR/usr/bin" \
  "$APPDIR/usr/lib" \
  "$APPDIR/usr/share/applications" \
  "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# ── Copy binary ───────────────────────────────────────────────────────────────
cp "$ZED_BIN" "$APPDIR/usr/bin/zed"
chmod +x "$APPDIR/usr/bin/zed"

# Copy bundled libs if present (libEGL, libwebrtc, etc.)
PARENT_DIR=$(dirname "$ZED_BIN_DIR")
for LIB_DIR in "$ZED_BIN_DIR/../lib" "$PARENT_DIR/lib"; do
  if [[ -d "$LIB_DIR" ]]; then
    cp -r "$LIB_DIR"/. "$APPDIR/usr/lib/"
    echo "Copied bundled libs from $LIB_DIR"
    break
  fi
done

# ── Desktop entry ─────────────────────────────────────────────────────────────
DESKTOP_FILE="$APPDIR/usr/share/applications/zed.desktop"
cat > "$DESKTOP_FILE" << DESKTOP
[Desktop Entry]
Name=Zed
GenericName=Text Editor
Comment=A high-performance, multiplayer code editor
Exec=zed %F
Icon=zed
Type=Application
Categories=Development;TextEditor;IDE;
MimeType=text/plain;inode/directory;
Keywords=editor;code;text;rust;
StartupWMClass=zed
X-AppImage-Version=$VERSION
DESKTOP

# Validate the desktop file before continuing
desktop-file-validate "$DESKTOP_FILE"
echo "Desktop file valid ✓"

# Symlink to AppDir root (required by AppImage spec)
cp "$DESKTOP_FILE" "$APPDIR/zed.desktop"

# ── Icon ──────────────────────────────────────────────────────────────────────
ICON_DEST_256="$APPDIR/usr/share/icons/hicolor/256x256/apps/zed.png"

# 1. Try to find an icon shipped inside the tarball
TARBALL_ICON=$(find . -maxdepth 8 -type f -name '*.png' \
  ! -path './AppDir/*' ! -path './.git/*' \
  | grep -iE 'icon|logo|zed' | head -1 || true)

if [[ -n "$TARBALL_ICON" ]]; then
  echo "Using bundled icon: $TARBALL_ICON"
  cp "$TARBALL_ICON" "$ICON_DEST_256"

else
  # 2. Try multiple upstream URL candidates (don't abort on curl failure)
  ICON_URLS=(
    "https://raw.githubusercontent.com/zed-industries/zed/main/assets/icons/zed_logo_256.png"
    "https://raw.githubusercontent.com/zed-industries/zed/main/assets/app_icon.png"
    "https://raw.githubusercontent.com/zed-industries/zed/main/assets/icon_512.png"
  )
  ICON_FETCHED=false
  for URL in "${ICON_URLS[@]}"; do
    if curl -sSfL --max-time 10 "$URL" -o "$ICON_DEST_256" 2>/dev/null; then
      echo "Icon downloaded from $URL"
      ICON_FETCHED=true
      break
    fi
  done

  if [[ "$ICON_FETCHED" != "true" ]]; then
    # 3. Fallback: generate a simple icon with ImageMagick (always works)
    echo "Generating placeholder icon with ImageMagick..."
    convert -size 256x256 xc:'#084CCF' \
      -fill white -font DejaVu-Sans-Bold -pointsize 120 \
      -gravity Center -annotate 0 'Z' \
      "$ICON_DEST_256"
  fi
fi

# Copy icon to AppDir root (both .png and symlink without extension)
cp "$ICON_DEST_256" "$APPDIR/zed.png"

# ── AppRun entrypoint ─────────────────────────────────────────────────────────
cat > "$APPDIR/AppRun" << 'APPRUN'
#!/bin/bash
SELF_DIR="$(dirname "$(readlink -f "$0")")"
export PATH="$SELF_DIR/usr/bin:$PATH"

if [[ -d "$SELF_DIR/usr/lib" ]]; then
  export LD_LIBRARY_PATH="$SELF_DIR/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

exec "$SELF_DIR/usr/bin/zed" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "==> AppDir layout:"
find "$APPDIR" -not -path '*/\.*' | sort
echo ""
echo "==> AppDir ready ✓"
