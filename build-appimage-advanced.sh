#!/bin/bash
set -e

# Advanced BigOcrPDF AppImage Builder using python-appimage
# This provides better portability by bundling Python and system libraries

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build/appimage-advanced"
APPDIR="$BUILD_DIR/BigOcrPDF.AppDir"
PYTHON_APPIMAGE_VERSION="3.11.14"

DEFAULT_APP_VERSION="$(sed -n 's/^VERSION = "\([^"]*\)"/\1/p' "$SCRIPT_DIR/src/bigocrpdf/version.py" | head -n1)"
if [ -z "$DEFAULT_APP_VERSION" ]; then
    DEFAULT_APP_VERSION="0.0.0"
fi
APP_VERSION="${APP_VERSION:-$DEFAULT_APP_VERSION}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo "========================================"
echo "BigOcrPDF AppImage Builder (Advanced)"
echo "Using python-appimage for portability"
echo "========================================"
echo ""

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    for cmd in python3 pip3 wget patchelf pkg-config; do
        command -v $cmd >/dev/null 2>&1 || error "$cmd is required but not installed"
    done
    
    # Check for Python development headers
    if ! pkg-config --exists python3; then
        error "Python development headers not found. Install python3-dev (Debian/Ubuntu) or python3-devel (Fedora/RHEL)"
    fi
    
    # Check for Cairo development libraries
    if ! pkg-config --exists cairo; then
        error "Cairo development libraries not found. Install libcairo2-dev (Debian/Ubuntu) or cairo-devel (Fedora/RHEL)"
    fi
    
    # PyGObject on newer distros expects girepository-2.0; older distros expose gobject-introspection-1.0.
    if pkg-config --exists girepository-2.0; then
        :
    elif pkg-config --exists gobject-introspection-1.0; then
        :
    else
        error "GObject Introspection development files not found. Install libgirepository-2.0-dev (Ubuntu 24.04+) or libgirepository1.0-dev (older Debian/Ubuntu)"
    fi
    
    info "Prerequisites OK"
}

# Download tools
download_tools() {
    info "Downloading build tools..."
    
    mkdir -p "$BUILD_DIR/tools"
    cd "$BUILD_DIR/tools"
    
    # Download python-appimage
    PYTHON_APPIMAGE_NAME="python3.11.14-cp311-cp311-manylinux2014_x86_64.AppImage"
    if [ ! -f "$PYTHON_APPIMAGE_NAME" ]; then
        info "Downloading python-appimage 3.11.14..."
        wget -q --show-progress "https://github.com/niess/python-appimage/releases/download/python3.11/$PYTHON_APPIMAGE_NAME"
        chmod +x "$PYTHON_APPIMAGE_NAME"
    fi
    
    # Download appimagetool
    if [ ! -f "appimagetool-x86_64.AppImage" ]; then
        info "Downloading appimagetool..."
        wget -q --show-progress "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
        chmod +x "appimagetool-x86_64.AppImage"
    fi
    
    cd "$SCRIPT_DIR"
    info "Tools downloaded"
}

# Extract python-appimage
extract_python() {
    info "Extracting Python AppImage..."
    
    cd "$BUILD_DIR/tools"
    
    rm -rf "$APPDIR"
    
    # Extract the python AppImage
    PYTHON_APPIMAGE_NAME="python3.11.14-cp311-cp311-manylinux2014_x86_64.AppImage"
    ./"$PYTHON_APPIMAGE_NAME" --appimage-extract >/dev/null
    
    # Move to AppDir
    mv squashfs-root "$APPDIR"
    
    cd "$SCRIPT_DIR"
    info "Python extracted to AppDir"
}

# Install application and dependencies
install_app() {
    info "Installing BigOcrPDF and dependencies..."
    
    # Use the bundled Python to install packages
    export PYTHONHOME="$APPDIR/opt/python3.11"
    export PATH="$APPDIR/opt/python3.11/bin:$PATH"
    export LD_LIBRARY_PATH="$APPDIR/opt/python3.11/lib:$LD_LIBRARY_PATH"
    
    # Create convenience symlinks
    cd "$APPDIR/opt/python3.11/bin"
    ln -sf python3.11 python3
    ln -sf python3.11 python
    ln -sf python3.11 pip3
    ln -sf pip3.11 pip
    cd "$SCRIPT_DIR"
    
    # Install the application
    "$APPDIR/opt/python3.11/bin/pip3.11" install --no-cache-dir "$SCRIPT_DIR"
    
    # Copy wrapper scripts from usr/bin
    if [ -f "$SCRIPT_DIR/usr/bin/bigocrimage" ]; then
        cp "$SCRIPT_DIR/usr/bin/bigocrimage" "$APPDIR/opt/python3.11/bin/"
        chmod +x "$APPDIR/opt/python3.11/bin/bigocrimage"
    fi
    
    # Install OCR runtime dependencies
    info "Installing onnxruntime..."
    "$APPDIR/opt/python3.11/bin/pip3.11" install --no-cache-dir \
        'onnxruntime>=1.16.0'
    
    info "Installing openvino..."
    "$APPDIR/opt/python3.11/bin/pip3.11" install --no-cache-dir \
        'openvino>=2023.0.0'

    info "Validating Python dependency graph..."
    "$APPDIR/opt/python3.11/bin/pip3.11" check
    
    # Create sitecustomize.py to redirect RapidOCR models path
    info "Creating sitecustomize.py for RapidOCR path redirection..."
    SITE_PACKAGES="$APPDIR/opt/python3.11/lib/python3.11/site-packages"
    cat > "$SITE_PACKAGES/sitecustomize.py" << 'SITECUSTOMIZE_EOF'
"""AppImage sitecustomize - redirects RapidOCR models to writable cache."""
import sys
import os
from pathlib import Path

# Only activate in AppImage environment
if os.environ.get('APPIMAGE') or os.environ.get('APPDIR'):
    cache_dir = Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) / 'bigocrpdf' / 'rapidocr'
    cache_dir.mkdir(parents=True, exist_ok=True)
    
    # Store the original __import__ function
    _original_import = __import__
    _patched_modules = set()
    
    def _custom_import(name, *args, **kwargs):
        """Custom import that patches rapidocr.utils.download_file after loading."""
        module = _original_import(name, *args, **kwargs)
        
        # Patch rapidocr.utils.download_file once it's imported
        if name == 'rapidocr.utils.download_file' and name not in _patched_modules:
            _patched_modules.add(name)
            if hasattr(module, 'ROOT_DIR'):
                module.ROOT_DIR = cache_dir
                # Also patch the instance variable if it exists
                if hasattr(module, 'root_dir'):
                    module.root_dir = cache_dir
        
        return module
    
    # Replace built-in __import__
    import builtins
    builtins.__import__ = _custom_import
SITECUSTOMIZE_EOF
    
    info "Application and dependencies installed"
    info "Note: RapidOCR models will be downloaded to ~/.cache/bigocrpdf/rapidocr on first use"
    info "      sitecustomize.py has been configured for automatic path redirection"
}

# Copy system libraries for GTK4 and GObject
bundle_system_libs() {
    info "Bundling system libraries..."
    
    mkdir -p "$APPDIR/usr/lib"
    mkdir -p "$APPDIR/usr/share/glib-2.0/schemas"
    
    # List of libraries to bundle (if available)
    LIBS=(
        "libgtk-4.so.1"
        "libadwaita-1.so.0"
        "libcairo.so.2"
        "libcairo-gobject.so.2"
        "libpango-1.0.so.0"
        "libpangocairo-1.0.so.0"
        "libgdk_pixbuf-2.0.so.0"
        "libgio-2.0.so.0"
        "libglib-2.0.so.0"
        "libgobject-2.0.so.0"
        "libgmodule-2.0.so.0"
        "libgraphene-1.0.so.0"
    )
    
    for lib in "${LIBS[@]}"; do
        # Find library path
        LIB_PATH=$(ldconfig -p | grep "$lib" | awk '{print $NF}' | head -1)
        if [ -n "$LIB_PATH" ] && [ -f "$LIB_PATH" ]; then
            info "  Copying $lib..."
            cp -L "$LIB_PATH" "$APPDIR/usr/lib/" 2>/dev/null || warn "  Could not copy $lib"
        else
            warn "  Library $lib not found on system"
        fi
    done
    
    # Copy GSettings schemas if available
    if [ -d "/usr/share/glib-2.0/schemas" ]; then
        cp -r /usr/share/glib-2.0/schemas/* "$APPDIR/usr/share/glib-2.0/schemas/" 2>/dev/null || true
        # Compile schemas
        if command -v glib-compile-schemas >/dev/null; then
            glib-compile-schemas "$APPDIR/usr/share/glib-2.0/schemas/" 2>/dev/null || warn "Could not compile GSettings schemas"
        fi
    fi
    
    info "System libraries bundled (some may require system installation)"
}

# Create custom AppRun
create_custom_apprun() {
    info "Creating custom AppRun..."
    
    # Backup original AppRun
    mv "$APPDIR/AppRun" "$APPDIR/AppRun.python" 2>/dev/null || true
    
    cat > "$APPDIR/AppRun" << 'APPRUN_EOF'
#!/bin/bash

APPDIR="$(dirname "$(readlink -f "$0")")"

# Set up Python environment
export PYTHONHOME="$APPDIR/opt/python3.11"
export PYTHONPATH="$APPDIR/opt/python3.11/lib/python3.11/site-packages"
export PATH="$APPDIR/opt/python3.11/bin:$PATH"
export LD_LIBRARY_PATH="$APPDIR/usr/lib:$APPDIR/opt/python3.11/lib:$LD_LIBRARY_PATH"

# XDG directories
export XDG_DATA_DIRS="$APPDIR/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# GTK/GDK settings
export GSETTINGS_SCHEMA_DIR="$APPDIR/usr/share/glib-2.0/schemas:${GSETTINGS_SCHEMA_DIR}"

# ONNX Runtime settings (reduce logging)
export ORT_LOGGING_LEVEL=3

# OpenVINO settings
export OPENVINO_DIR="$APPDIR/opt/python3.11"

# RapidOCR model handling - use unionfs-fuse to overlay writable on read-only
RAPIDOCR_CACHE="$XDG_CACHE_HOME/bigocrpdf/rapidocr"
RAPIDOCR_MODELS_READONLY="$APPDIR/opt/python3.11/lib/python3.11/site-packages/rapidocr/models"
RAPIDOCR_MODELS_WRITABLE="$RAPIDOCR_CACHE/models"
RAPIDOCR_MODELS_UNION="$RAPIDOCR_CACHE/union"

mkdir -p "$RAPIDOCR_MODELS_WRITABLE"
mkdir -p "$RAPIDOCR_MODELS_UNION"

# Try to use unionfs-fuse if available (overlay writable on read-only)
if command -v unionfs-fuse >/dev/null 2>&1; then
    # Unmount if already mounted
    fusermount -u "$RAPIDOCR_MODELS_UNION" 2>/dev/null || true
    
    # Mount union filesystem: writable overlay on read-only base
    unionfs-fuse -o cow,allow_other "$RAPIDOCR_MODELS_WRITABLE=RW:$RAPIDOCR_MODELS_READONLY=RO" "$RAPIDOCR_MODELS_UNION" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        # Successfully mounted union fs, tell Python to use it
        export PYTHONPATH="$RAPIDOCR_CACHE:$PYTHONPATH"
        
        # Create a stub rapidocr package that redirects to the union
        mkdir -p "$RAPIDOCR_CACHE/rapidocr"
        ln -sf "$RAPIDOCR_MODELS_UNION" "$RAPIDOCR_CACHE/rapidocr/models" 2>/dev/null || true
        
        # Cleanup function
        cleanup() {
            fusermount -u "$RAPIDOCR_MODELS_UNION" 2>/dev/null || true
        }
        trap cleanup EXIT
    else
        # unionfs-fuse failed, fall back to direct write cache
        export RAPIDOCR_MODEL_PATH="$RAPIDOCR_MODELS_WRITABLE"
        export RAPIDOCR_FONT_PATH="$RAPIDOCR_MODELS_WRITABLE"
    fi
else
    # No unionfs-fuse, use direct write to cache
    export RAPIDOCR_MODEL_PATH="$RAPIDOCR_MODELS_WRITABLE"
    export RAPIDOCR_FONT_PATH="$RAPIDOCR_MODELS_WRITABLE"
fi

# Determine which command to run
APPIMAGE_NAME="$(basename "$ARGV0" 2>/dev/null || basename "$0")"
BIGOCRPDF="$APPDIR/opt/python3.11/bin/bigocrpdf"
BIGOCRIMAGE="$APPDIR/opt/python3.11/bin/bigocrimage"

case "$APPIMAGE_NAME" in
    *bigocrimage*)
        exec "$BIGOCRIMAGE" "$@"
        ;;
    *editor*)
        exec "$BIGOCRPDF" --edit "$@"
        ;;
    *)
        # Check first argument
        if [ "$1" = "--edit" ] || [ "$1" = "-e" ]; then
            exec "$BIGOCRPDF" "$@"
        elif [ "$1" = "--image" ] || [ "$1" = "-i" ]; then
            shift
            exec "$BIGOCRIMAGE" "$@"
        else
            exec "$BIGOCRPDF" "$@"
        fi
        ;;
esac
APPRUN_EOF

    chmod +x "$APPDIR/AppRun"
    info "Custom AppRun created (with unionfs-fuse support)"
}

# Setup desktop integration
setup_desktop_integration() {
    info "Setting up desktop integration..."
    
    mkdir -p "$APPDIR/usr/share/applications"
    mkdir -p "$APPDIR/usr/share/icons/hicolor/scalable/apps"
    mkdir -p "$APPDIR/usr/share/metainfo"
    
    # Copy desktop files
    cp "$SCRIPT_DIR/usr/share/applications/"*.desktop "$APPDIR/usr/share/applications/"
    
    # Copy main desktop file to root
    cp "$SCRIPT_DIR/usr/share/applications/br.com.biglinux.bigocrpdf.desktop" \
       "$APPDIR/bigocrpdf.desktop"
    
    # Copy icons
    cp "$SCRIPT_DIR/usr/share/icons/hicolor/scalable/apps/"*.svg \
       "$APPDIR/usr/share/icons/hicolor/scalable/apps/"
    
    # Main icon for AppImage
    cp "$SCRIPT_DIR/usr/share/icons/hicolor/scalable/apps/bigocrpdf.svg" \
       "$APPDIR/bigocrpdf.svg"
    
    ln -sf bigocrpdf.svg "$APPDIR/.DirIcon"
    
    # Create AppStream metadata
    cat > "$APPDIR/usr/share/metainfo/br.com.biglinux.bigocrpdf.appdata.xml" << METADATA_EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>br.com.biglinux.bigocrpdf</id>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>GPL-3.0-or-later</project_license>
  <name>BigOcrPDF</name>
  <summary>Add OCR to your PDF documents - Powered by RapidOCR with ONNX Runtime and OpenVINO</summary>
  <description>
    <p>
      BigOcrPDF is a powerful, all-in-one OCR application that adds searchable 
      text layers to scanned PDFs, extracts text from images, and provides a 
      full-featured PDF editor.
    </p>
    <p>This AppImage includes:</p>
    <ul>
      <li>RapidOCR engine with ONNX Runtime support</li>
      <li>OpenVINO backend for optimized performance</li>
      <li>Complete Python environment with all dependencies</li>
      <li>GTK4 and Libadwaita for modern UI</li>
    </ul>
    <p>Features:</p>
    <ul>
      <li>OCR for scanned PDFs in 80+ languages</li>
      <li>Text extraction from images and screenshots</li>
      <li>PDF editor with page management and merging</li>
      <li>Batch processing with checkpoint/resume</li>
      <li>Export to PDF/A-2b, TXT, or ODF formats</li>
      <li>Document dewarping and perspective correction</li>
    </ul>
  </description>
  <launchable type="desktop-id">br.com.biglinux.bigocrpdf.desktop</launchable>
  <url type="homepage">https://www.biglinux.com.br</url>
  <url type="bugtracker">https://github.com/biglinux/bigocrpdf/issues</url>
  <developer_name>BigLinux Team</developer_name>
  <content_rating type="oars-1.1" />
  <releases>
    <release version="${APP_VERSION}" date="2026-03-11">
      <description>
        <p>Initial AppImage release with bundled ONNX Runtime and OpenVINO</p>
      </description>
    </release>
  </releases>
</component>
METADATA_EOF
    
    info "Desktop integration setup complete"
}

# Build final AppImage
build_appimage() {
    info "Building final AppImage..."
    
    cd "$BUILD_DIR"
    
    export VERSION="$APP_VERSION"
    export ARCH=x86_64
    
    # Run appimagetool
    ./tools/appimagetool-x86_64.AppImage \
        --no-appstream \
        "$APPDIR" \
        "BigOcrPDF-${APP_VERSION}-x86_64.AppImage"
    
    if [ -f "BigOcrPDF-${APP_VERSION}-x86_64.AppImage" ]; then
        chmod +x "BigOcrPDF-${APP_VERSION}-x86_64.AppImage"
        
        # Copy to dist
        mkdir -p "$SCRIPT_DIR/dist"
        cp "BigOcrPDF-${APP_VERSION}-x86_64.AppImage" "$SCRIPT_DIR/dist/"
        
        # Get file size
        SIZE=$(du -h "$SCRIPT_DIR/dist/BigOcrPDF-${APP_VERSION}-x86_64.AppImage" | cut -f1)
        
        echo ""
        echo "=========================================="
        echo -e "${GREEN}SUCCESS!${NC}"
        echo "=========================================="
        echo "AppImage created: BigOcrPDF-${APP_VERSION}-x86_64.AppImage"
        echo "Size: $SIZE"
        echo "Location: $SCRIPT_DIR/dist/"
        echo ""
        echo "This AppImage includes:"
        echo "  ✓ Python 3.11.14 with all dependencies"
        echo "  ✓ ONNX Runtime for OCR acceleration"
        echo "  ✓ OpenVINO for Intel hardware optimization"
        echo "  ✓ RapidOCR engine"
        echo "  ✓ All required Python packages"
        echo ""
        echo "Usage:"
        echo "  ./dist/BigOcrPDF-${APP_VERSION}-x86_64.AppImage          # Main PDF OCR"
        echo "  ./dist/BigOcrPDF-${APP_VERSION}-x86_64.AppImage --edit   # PDF Editor"
        echo "  ./dist/BigOcrPDF-${APP_VERSION}-x86_64.AppImage --image  # Image OCR"
        echo ""
        echo "Note: GTK4 and Libadwaita must be installed on the target system"
        echo "      for the GUI to work properly."
        echo ""
    else
        error "Failed to create AppImage"
    fi
}

# Main execution
main() {
    check_prerequisites
    download_tools
    extract_python
    install_app
    bundle_system_libs
    create_custom_apprun
    setup_desktop_integration
    build_appimage
}

main "$@"
