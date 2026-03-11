# Building BigOcrPDF AppImage

This repository supports a single AppImage build method:

- `build-appimage-advanced.sh`

The advanced builder uses `python-appimage` to bundle a complete Python runtime and all required Python dependencies.

## Why only one method?

Older local methods were removed because they were either broken or incomplete:

- `build-appimage.sh` (removed): venv-based build did not produce a complete portable Python runtime.
- `build-appimage-simple.sh` (removed): experimental and incomplete.

## What gets bundled

The produced AppImage includes:

- Python 3.11 runtime
- BigOcrPDF application and Python dependencies
- RapidOCR
- ONNX Runtime
- OpenVINO

Note: GTK4 and Libadwaita are expected on the target system.

## Prerequisites

Use the checker script:

```bash
./check-appimage-prereqs.sh
```

Manual package install examples:

```bash
# Debian/Ubuntu
sudo apt install python3 python3-pip python3-venv python3-dev wget patchelf \
                 desktop-file-utils pkg-config libcairo2-dev libgirepository1.0-dev

# Fedora/RHEL
sudo dnf install python3 python3-pip python3-devel wget patchelf \
                 desktop-file-utils pkgconfig cairo-devel gobject-introspection-devel

# Arch Linux
sudo pacman -S python python-pip wget patchelf desktop-file-utils \
               pkgconf cairo gobject-introspection
```

## Build locally

```bash
chmod +x build-appimage-advanced.sh
./build-appimage-advanced.sh
```

By default this creates:

```text
dist/BigOcrPDF-3.0.0-x86_64.AppImage
```

You can override the version at build time:

```bash
APP_VERSION=3.0.1 ./build-appimage-advanced.sh
```

## Run the AppImage

```bash
# Main PDF OCR UI
./dist/BigOcrPDF-3.0.0-x86_64.AppImage

# PDF editor mode
./dist/BigOcrPDF-3.0.0-x86_64.AppImage --edit

# Image OCR mode
./dist/BigOcrPDF-3.0.0-x86_64.AppImage --image
```

## GitHub Actions release publishing

Automated release publishing is configured in:

- `.github/workflows/build-appimage-release.yml`

Trigger:

- Push a tag matching `v*` (for example, `v3.0.1`).

Behavior:

1. Installs AppImage build dependencies.
2. Builds using `build-appimage-advanced.sh`.
3. Passes `APP_VERSION` from the pushed tag (`v3.0.1` becomes `3.0.1`).
4. Uploads `dist/*.AppImage` as workflow artifact.
5. Publishes the AppImage to the GitHub release for that tag.

### Release flow

```bash
git tag -a v3.0.1 -m "Version 3.0.1"
git push origin v3.0.1
```

After the workflow finishes, the release will contain the built AppImage asset.

## Troubleshooting

### Build fails on missing headers

Install Python/Cairo/GObject development packages and rerun:

```bash
./check-appimage-prereqs.sh
```

### AppImage fails due to GTK/Libadwaita

Install runtime GUI libraries on target system:

```bash
# Debian/Ubuntu
sudo apt install libgtk-4-1 libadwaita-1-0

# Fedora/RHEL
sudo dnf install gtk4 libadwaita

# Arch Linux
sudo pacman -S gtk4 libadwaita
```

## Resources

- [AppImage Documentation](https://docs.appimage.org/)
- [python-appimage](https://github.com/niess/python-appimage)
- [AppImageKit](https://github.com/AppImage/AppImageKit)
