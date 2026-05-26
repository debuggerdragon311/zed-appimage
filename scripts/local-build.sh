#!/usr/bin/env bash
# local-build.sh — Build a Zed AppImage locally for testing
# Usage: bash local-build.sh [version] [arch]
#   version — e.g. v1.3.7 (default: latest)
#   arch    — x86_64 | aarch64 (default: x86_64)

set -euo pipefail

VERSION="${1:-}"
ARCH="${2:-x86_64}"
WORKDIR="$(mktemp -d)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

echo "==> Work dir: $WORKDIR"
cd "$WORKDIR"

# ── Resolve version ───────────────────────────────────────────────────────────
if [[ -z "$VERSION" ]]; then
  echo "==> Fetching latest Zed release..."
  VERSION=$(curl -sSf \
    https://api.github.com/repos/zed-industries/zed/releases/latest \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
fi
echo "==> Target version: $VERSION"
VERSION_NUM="${VERSION#v}"

# ── Download appimagetool ─────────────────────────────────────────────────────
if ! command -v appimagetool &>/dev/null; then
  echo "==> Downloading appimagetool..."
  wget -q \
    "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${ARCH}.AppImage" \
    -O /tmp/appimagetool
  chmod +x /tmp/appimagetool
  export PATH="/tmp:$PATH"
fi
export APPIMAGE_EXTRACT_AND_RUN=1

# ── Download Zed tarball ──────────────────────────────────────────────────────
URL="https://github.com/zed-industries/zed/releases/download/${VERSION}/zed-linux-${ARCH}.tar.gz"
echo "==> Downloading $URL"
wget -q "$URL" -O zed.tar.gz
tar -xzf zed.tar.gz

# ── Build AppDir ──────────────────────────────────────────────────────────────
cp -r "$SCRIPT_DIR/../AppDir" ./AppDir 2>/dev/null || mkdir -p AppDir
bash "$SCRIPT_DIR/build-appdir.sh" "$ARCH" "$VERSION_NUM"

# ── Package ───────────────────────────────────────────────────────────────────
OUTPUT="${OLDPWD}/Zed-${VERSION_NUM}-${ARCH}.AppImage"
ARCH=$ARCH appimagetool AppDir "$OUTPUT"
chmod +x "$OUTPUT"

echo ""
echo "✅ Done! AppImage: $OUTPUT"
echo "   Size: $(du -sh "$OUTPUT" | cut -f1)"
sha256sum "$OUTPUT"
