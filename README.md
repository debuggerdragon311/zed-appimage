# Zed AppImage

[![Zed](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/zed-industries/zed/main/assets/badge/v0.json)](https://zed.dev)
[![Build](https://github.com/debuggerdragon311/zed-appimage/actions/workflows/build-appimage.yml/badge.svg)](https://github.com/debuggerdragon311/zed-appimage/actions/workflows/build-appimage.yml)
[![Latest Release](https://img.shields.io/github/v/release/debuggerdragon311/zed-appimage?label=AppImage)](https://github.com/debuggerdragon311/zed-appimage/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](./LICENSE)
[![Upstream License](https://img.shields.io/badge/upstream%20license-AGPL--3.0-blue)](https://github.com/zed-industries/zed/blob/main/LICENSE-AGPL)

Unofficial AppImage packaging of [Zed](https://zed.dev) — a high-performance, multiplayer code editor from the creators of [Atom](https://github.com/atom/atom) and [Tree-sitter](https://github.com/tree-sitter/tree-sitter).

Zed ships Linux binaries as `.tar.gz` tarballs only. This repository automatically repackages every upstream release into a portable, single-file AppImage that runs on any Linux distribution without installation.

---

### Download

Go to the [Releases](https://github.com/debuggerdragon311/zed-appimage/releases/latest) page and download the AppImage for your architecture.

| File | Architecture |
|---|---|
| `zed-x86_64.AppImage` | Intel / AMD 64-bit (most Linux PCs) |
| `zed-aarch64.AppImage` | ARM 64-bit (Raspberry Pi 4+, Asahi Linux) |

Each release also includes a `.sha256` checksum file.

---

### Installation

```bash
# 1. Download (replace arch as needed)
wget https://github.com/debuggerdragon311/zed-appimage/releases/latest/download/zed-x86_64.AppImage

# 2. Make executable
chmod +x zed-x86_64.AppImage

# 3. Run
./zed-x86_64.AppImage
```

**Optional — integrate with your desktop** (adds Zed to your app menu with icon):

```bash
./zed-x86_64.AppImage --appimage-install

# To remove desktop integration later
./zed-x86_64.AppImage --appimage-remove
```

**Verify checksum:**

```bash
sha256sum -c zed-x86_64.AppImage.sha256
```

---

### How It Works

Every 6 hours a GitHub Actions workflow checks the [upstream Zed releases](https://github.com/zed-industries/zed/releases) for a new version. When one is found, AppImages for both architectures are built in parallel and published here automatically.

```
zed-linux-x86_64.tar.gz  (official upstream binary)
           │
           ▼
   scripts/build-appdir.sh   →   assembles AppDir/
           │
           ▼
       appimagetool           →   squashes into .AppImage
           │
           ▼
     GitHub Release           →   uploaded with .sha256 checksum
```

You can also trigger a build manually for a specific version:

1. Go to **Actions → Build Zed AppImage → Run workflow**
2. Enter a version tag such as `v1.3.7`
3. Click **Run workflow**

Or build locally:

```bash
# Requires: wget, appimagetool, libfuse2, desktop-file-utils, imagemagick
bash scripts/local-build.sh v1.3.7 x86_64
```

---

### Disclaimer

This project is not affiliated with or endorsed by [Zed Industries](https://zed.dev).
All binaries are sourced unmodified from the [official Zed releases](https://github.com/zed-industries/zed/releases). AppImage packaging only adds an `AppRun` launcher and desktop integration metadata — no source modifications are made.

- For bugs in Zed itself → [zed-industries/zed](https://github.com/zed-industries/zed/issues)
- For AppImage packaging issues → [open an issue here](https://github.com/debuggerdragon311/zed-appimage/issues)
