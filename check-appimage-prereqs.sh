#!/bin/bash

# BigOcrPDF AppImage prerequisites checker.
# Run this before building to ensure all requirements are met.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "BigOcrPDF AppImage Prerequisites Checker"
echo "=========================================="
echo ""

MISSING=0

check_command() {
    local cmd=$1
    local package=$2

    if command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $cmd is installed"
        return 0
    else
        echo -e "${RED}✗${NC} $cmd is NOT installed"
        if [ -n "$package" ]; then
            echo -e "   Install with: ${BLUE}$package${NC}"
        fi
        MISSING=$((MISSING + 1))
        return 1
    fi
}

check_library() {
    local lib=$1
    local package=$2

    if ldconfig -p 2>/dev/null | grep -q "$lib"; then
        echo -e "${GREEN}✓${NC} $lib is available"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} $lib is NOT available (optional for AppImage, required on target system)"
        if [ -n "$package" ]; then
            echo -e "   Install with: ${BLUE}$package${NC}"
        fi
        return 1
    fi
}

echo "Core Build Tools:"
echo "----------------"

# Detect package manager
if command -v apt >/dev/null 2>&1; then
    PKG_MGR="apt"
    PY_CMD="sudo apt install python3 python3-pip python3-venv python3-dev"
    WGET_CMD="sudo apt install wget"
    PATCHELF_CMD="sudo apt install patchelf"
    DESKTOP_CMD="sudo apt install desktop-file-utils"
    CAIRO_CMD="sudo apt install libcairo2-dev pkg-config"
    GOBJ_CMD="sudo apt install libgirepository1.0-dev"
elif command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
    PY_CMD="sudo dnf install python3 python3-pip python3-devel"
    WGET_CMD="sudo dnf install wget"
    PATCHELF_CMD="sudo dnf install patchelf"
    DESKTOP_CMD="sudo dnf install desktop-file-utils"
    CAIRO_CMD="sudo dnf install cairo-devel pkgconfig"
    GOBJ_CMD="sudo dnf install gobject-introspection-devel"
elif command -v pacman >/dev/null 2>&1; then
    PKG_MGR="pacman"
    PY_CMD="sudo pacman -S python python-pip"
    WGET_CMD="sudo pacman -S wget"
    PATCHELF_CMD="sudo pacman -S patchelf"
    DESKTOP_CMD="sudo pacman -S desktop-file-utils"
    CAIRO_CMD="sudo pacman -S cairo pkgconf"
    GOBJ_CMD="sudo pacman -S gobject-introspection"
else
    PKG_MGR="unknown"
    PY_CMD="install python3 and pip with your package manager"
    WGET_CMD="install wget with your package manager"
    PATCHELF_CMD="install patchelf with your package manager"
    DESKTOP_CMD="install desktop-file-utils with your package manager"
    CAIRO_CMD="install cairo development packages"
    GOBJ_CMD="install gobject-introspection development packages"
fi

check_command "python3" "$PY_CMD"
check_command "pip3" "$PY_CMD"
check_command "wget" "$WGET_CMD"
check_command "patchelf" "$PATCHELF_CMD"
check_command "pkg-config" "$CAIRO_CMD"

echo ""
echo "Python Version:"
echo "--------------"
if command -v python3 >/dev/null 2>&1; then
    PY_VER=$(python3 --version 2>&1 | cut -d' ' -f2)
    echo -e "Python version: ${GREEN}$PY_VER${NC}"

    # Check if version is >= 3.10
    PY_MAJOR=$(echo "$PY_VER" | cut -d'.' -f1)
    PY_MINOR=$(echo "$PY_VER" | cut -d'.' -f2)

    if [ "$PY_MAJOR" -ge 3 ] && [ "$PY_MINOR" -ge 10 ]; then
        echo -e "${GREEN}✓${NC} Python version is compatible (>=3.10 required)"
    else
        echo -e "${RED}✗${NC} Python version is too old (>=3.10 required)"
        MISSING=$((MISSING + 1))
    fi
fi

echo ""
echo "Python Development Headers:"
echo "--------------------------"
if pkg-config --exists python3 2>/dev/null; then
    PY_DEV_VER=$(pkg-config --modversion python3 2>/dev/null)
    echo -e "${GREEN}✓${NC} Python development headers found (version $PY_DEV_VER)"
else
    echo -e "${RED}✗${NC} Python development headers NOT found"
    if [ -n "$PY_CMD" ]; then
        echo -e "   Install with: ${BLUE}$PY_CMD${NC}"
    fi
    MISSING=$((MISSING + 1))
fi

echo ""
echo "Cairo Development Libraries:"
echo "---------------------------"
if pkg-config --exists cairo 2>/dev/null; then
    CAIRO_VER=$(pkg-config --modversion cairo 2>/dev/null)
    echo -e "${GREEN}✓${NC} Cairo development libraries found (version $CAIRO_VER)"
else
    echo -e "${RED}✗${NC} Cairo development libraries NOT found"
    if [ -n "$CAIRO_CMD" ]; then
        echo -e "   Install with: ${BLUE}$CAIRO_CMD${NC}"
    fi
    MISSING=$((MISSING + 1))
fi

echo ""
echo "GObject Introspection:"
echo "---------------------"
if pkg-config --exists gobject-introspection-1.0 2>/dev/null; then
    GI_VER=$(pkg-config --modversion gobject-introspection-1.0 2>/dev/null)
    echo -e "${GREEN}✓${NC} GObject Introspection found (version $GI_VER)"
else
    echo -e "${RED}✗${NC} GObject Introspection development files NOT found"
    if [ -n "$GOBJ_CMD" ]; then
        echo -e "   Install with: ${BLUE}$GOBJ_CMD${NC}"
    fi
    MISSING=$((MISSING + 1))
fi

echo ""
echo "Target System Runtime Libraries (required on systems running the AppImage):"
echo "-------------------------------------------------------------------------"

if [ "$PKG_MGR" = "apt" ]; then
    GTK_CMD="sudo apt install libgtk-4-1 libadwaita-1-0"
elif [ "$PKG_MGR" = "dnf" ]; then
    GTK_CMD="sudo dnf install gtk4 libadwaita"
elif [ "$PKG_MGR" = "pacman" ]; then
    GTK_CMD="sudo pacman -S gtk4 libadwaita"
else
    GTK_CMD="install gtk4 and libadwaita with your package manager"
fi

check_library "libgtk-4.so" "$GTK_CMD"
check_library "libadwaita-1.so" "$GTK_CMD"
check_library "libcairo.so" "install cairo development packages"
check_library "libgobject-2.0.so" "install glib2 development packages"

echo ""
echo "Optional Tools:"
echo "--------------"

if command -v glib-compile-schemas >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} glib-compile-schemas available"
else
    echo -e "${YELLOW}⚠${NC} glib-compile-schemas not available (optional, for GSettings schemas)"
    if [ -n "$DESKTOP_CMD" ]; then
        echo -e "   Install with: ${BLUE}$DESKTOP_CMD${NC}"
    fi
fi

echo ""
echo "Disk Space:"
echo "----------"

AVAILABLE=$(df -h . | awk 'NR==2 {print $4}')
echo "Available space in current directory: $AVAILABLE"
echo "Required space: ~500MB for build artifacts, ~200-300MB for final AppImage"

echo ""
echo "=========================================="

if [ $MISSING -eq 0 ]; then
    echo -e "${GREEN}✓ All required prerequisites are met!${NC}"
    echo ""
    echo "Build command:"
    echo -e "  ${BLUE}./build-appimage-advanced.sh${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}✗ $MISSING required prerequisites are missing${NC}"
    echo ""
    echo "Please install the missing requirements and run this check again."
    echo ""

    if [ "$PKG_MGR" != "unknown" ]; then
        echo "Quick install (all required build packages):"
        if [ "$PKG_MGR" = "apt" ]; then
            echo -e "  ${BLUE}sudo apt update && sudo apt install -y python3 python3-pip python3-venv python3-dev wget patchelf desktop-file-utils pkg-config libcairo2-dev libgirepository1.0-dev libgtk-4-1 libadwaita-1-0${NC}"
        elif [ "$PKG_MGR" = "dnf" ]; then
            echo -e "  ${BLUE}sudo dnf install -y python3 python3-pip python3-devel wget patchelf desktop-file-utils pkgconfig cairo-devel gobject-introspection-devel gtk4 libadwaita${NC}"
        elif [ "$PKG_MGR" = "pacman" ]; then
            echo -e "  ${BLUE}sudo pacman -S --needed python python-pip wget patchelf desktop-file-utils pkgconf cairo gobject-introspection gtk4 libadwaita${NC}"
        fi
        echo ""
    fi

    exit 1
fi
