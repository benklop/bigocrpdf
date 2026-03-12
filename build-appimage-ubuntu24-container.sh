#!/usr/bin/env bash
set -euo pipefail

# Build BigOcrPDF AppImage inside an Ubuntu 24.04 container.
# Supports Docker and Podman; defaults to Docker when both are available.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$SCRIPT_DIR"

CONTAINER_ENGINE="${CONTAINER_ENGINE:-}"
if [ -z "$CONTAINER_ENGINE" ]; then
    if command -v docker >/dev/null 2>&1; then
        CONTAINER_ENGINE="docker"
    elif command -v podman >/dev/null 2>&1; then
        CONTAINER_ENGINE="podman"
    else
        echo "[ERROR] Neither docker nor podman is installed." >&2
        exit 1
    fi
fi

if ! command -v "$CONTAINER_ENGINE" >/dev/null 2>&1; then
    echo "[ERROR] Container engine '$CONTAINER_ENGINE' was not found in PATH." >&2
    exit 1
fi

IMAGE="${APPIMAGE_BUILD_IMAGE:-ubuntu:25.04}"
APP_VERSION_VALUE="${APP_VERSION:-}"

echo "[INFO] Using container engine: $CONTAINER_ENGINE"
echo "[INFO] Using image: $IMAGE"

"$CONTAINER_ENGINE" run --rm \
    -e APP_VERSION="$APP_VERSION_VALUE" \
    -v "$WORKSPACE_DIR:/workspace:z" \
    -w /workspace \
    "$IMAGE" \
    bash -lc '
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates \
    python3 \
    python3-pip \
    python3-dev \
    wget \
    patchelf \
    file \
    desktop-file-utils \
    pkg-config \
    libcairo2-dev \
    gobject-introspection \
    libgirepository-2.0-dev \
    libgtk-4-1 \
    libadwaita-1-0 \
    libgraphene-1.0-0 \
    libgdk-pixbuf-2.0-0 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libgstreamer1.0-0 \
    libgstreamer-plugins-base1.0-0 \
    liblcms2-2 \
    libopenjp2-7 \
    gir1.2-adw-1 \
    gir1.2-gtk-4.0 \
    gir1.2-gdkpixbuf-2.0 \
    gir1.2-pango-1.0 \
    gir1.2-glib-2.0

bash /workspace/build-appimage-advanced.sh
'
