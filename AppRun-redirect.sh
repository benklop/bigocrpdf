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

# ONNX Runtime settings
export ORT_LOGGING_LEVEL=3

# OpenVINO settings
export OPENVINO_DIR="$APPDIR/opt/python3.11"

# RapidOCR filesystem redirection
# Create writable cache for RapidOCR models
RAPIDOCR_CACHE="$XDG_CACHE_HOME/bigocrpdf/rapidocr"
mkdir -p "$RAPIDOCR_CACHE"

# Create a Python sitecustomize.py that redirects the models path
SITE_PACKAGES="$APPDIR/opt/python3.11/lib/python3.11/site-packages"
cat > "$SITE_PACKAGES/sitecustomize_bigocrpdf.py" << 'PYSCRIPT'
import sys
import os
from pathlib import Path

# Redirect RapidOCR models directory to writable cache
cache_dir = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache')) / 'bigocrpdf' / 'rapidocr'
cache_dir.mkdir(parents=True, exist_ok=True)

# Monkey-patch rapidocr before it's imported
class RapidOCRRedirector:
    def find_module(self, fullname, path=None):
        if fullname == 'rapidocr' or fullname.startswith('rapidocr.'):
            return self
        return None
    
    def load_module(self, fullname):
        if fullname in sys.modules:
            return sys.modules[fullname]
        
        # Import the real module
        import importlib
        mod = importlib.import_module(fullname)
        
        # If this is the rapidocr.utils.download_file module, patch it
        if fullname == 'rapidocr.utils.download_file':
            # Patch the ROOT_DIR or model directory
            if hasattr(mod, 'ROOT_DIR'):
                mod.ROOT_DIR = cache_dir
        
        # If this is the main rapidocr module, patch model paths
        if fullname == 'rapidocr':
            import importlib.util
            spec = importlib.util.find_spec('rapidocr')
            if spec and spec.origin:
                pkg_dir = Path(spec.origin).parent
                models_dir = pkg_dir / 'models'
                
                # Replace any reference to the read-only models dir
                if hasattr(mod, 'MODELS_DIR'):
                    mod.MODELS_DIR = cache_dir
                if hasattr(mod, 'get_model_dir'):
                    original_get_model_dir = mod.get_model_dir
                    def patched_get_model_dir(*args, **kwargs):
                        return str(cache_dir)
                    mod.get_model_dir = patched_get_model_dir
        
        return mod

# Install the import hook
sys.meta_path.insert(0, RapidOCRRedirector())
PYSCRIPT

# Add to PYTHONPATH so sitecustomize runs
export PYTHONPATH="$SITE_PACKAGES:$PYTHONPATH"
# Force Python to run the sitecustomize
export PYTHONSTARTUP="$SITE_PACKAGES/sitecustomize_bigocrpdf.py"

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
