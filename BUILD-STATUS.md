# AppImage Build Status

## Current support

BigOcrPDF supports one AppImage build path:

- `build-appimage-advanced.sh`

This is the only maintained and tested script for local and CI builds.

## Removed scripts

The following scripts were removed from active use:

- `build-appimage.sh` (broken venv-based portability)
- `build-appimage-simple.sh` (experimental/incomplete)

## Automation

AppImage build and publication are automated via:

- `.github/workflows/build-appimage-release.yml`

Trigger:

- Push tags matching `v*`.

Result:

- The workflow builds `dist/*.AppImage` and attaches it to the GitHub release for that tag.

## Manual build quick start

```bash
./check-appimage-prereqs.sh
./build-appimage-advanced.sh
```
