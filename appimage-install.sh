#!/bin/bash

# Script to install an AppImage and create a desktop menu entry.
# Usage: ./install_appimage.sh <path-to-appimage>

set -e

# check if an argument is provided
if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <path-to-appimage>"
    exit 1
fi

APPIMAGE_SRC="$1"

# Check if file exists
if [[ ! -f "$APPIMAGE_SRC" ]]; then
    echo "Error: File $APPIMAGE_SRC not found."
    exit 1
fi

# Configuration
INSTALL_BASE="/usr/local/makoto"
DESKTOP_DIR="/usr/local/share/applications"
ICON_DEST_DIR="/usr/local/share/icons"

# Ensure absolute path
APPIMAGE_SRC=$(readlink -f "$APPIMAGE_SRC")
APP_FILENAME=$(basename "$APPIMAGE_SRC")
APP_INSTALL_PATH="$INSTALL_BASE/$APP_FILENAME"

echo "Installing $APP_FILENAME to $INSTALL_BASE..."

# Create target directory
sudo mkdir -p "$INSTALL_BASE"

# Copy the AppImage
sudo cp "$APPIMAGE_SRC" "$APP_INSTALL_PATH"
sudo chmod +x "$APP_INSTALL_PATH"

# Extract metadata to a temporary directory
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
cd "$TMP_DIR"

echo "Extracting desktop file and icon from AppImage..."

# Extract a single path (or glob) from the AppImage into ./squashfs-root.
extract() {
    "$APP_INSTALL_PATH" --appimage-extract "$1" > /dev/null 2>&1 || true
}

# AppImages usually ship the top-level .desktop file and icon as symlinks into
# usr/share/..., and a selective extraction only extracts the link itself.
# Follow the symlink chain, extracting each target, and print the final path.
resolve() {
    local path="$1"
    local i target rel
    for (( i = 0; i < 10; i++ )); do
        [[ -L "$path" ]] || break
        target=$(readlink "$path")
        if [[ "$target" == /* ]]; then
            # Absolute links are relative to the AppImage root.
            rel="${target#/}"
        else
            rel=$(realpath -m -s --relative-to=squashfs-root "$(dirname "$path")/$target")
        fi
        extract "$rel"
        path="squashfs-root/$rel"
    done
    echo "$path"
}

# Per the AppImage spec, the .desktop file, the icon and .DirIcon live at the
# top level, so extract just those to avoid a full extraction.
extract "*.desktop"
extract "*.png"
extract "*.svg"
extract ".DirIcon"

# Check if extraction worked
if [[ ! -d "squashfs-root" ]]; then
    echo "Warning: Could not extract metadata using --appimage-extract. Trying full extraction..."
    "$APP_INSTALL_PATH" --appimage-extract > /dev/null 2>&1
fi

# Find the extracted files
DESKTOP_FILE=$(find squashfs-root -maxdepth 1 -name "*.desktop" -print -quit)
if [[ -n "$DESKTOP_FILE" ]]; then
    DESKTOP_FILE=$(resolve "$DESKTOP_FILE")
fi

# Prefer the icon named by the desktop file's Icon= key, then .DirIcon.
ICON_FILE=""
if [[ -f "$DESKTOP_FILE" ]]; then
    ICON_KEY=$(sed -n 's/^Icon=//p' "$DESKTOP_FILE" | head -n 1)
    for ext in svg png; do
        if [[ -n "$ICON_KEY" && -e "squashfs-root/$ICON_KEY.$ext" ]]; then
            ICON_FILE="squashfs-root/$ICON_KEY.$ext"
            break
        fi
    done
fi
if [[ -z "$ICON_FILE" && -e "squashfs-root/.DirIcon" ]]; then
    ICON_FILE="squashfs-root/.DirIcon"
fi
if [[ -z "$ICON_FILE" ]]; then
    ICON_FILE=$(find squashfs-root \( -name "*.png" -o -name "*.svg" \) -print -quit)
fi
if [[ -n "$ICON_FILE" ]]; then
    ICON_FILE=$(resolve "$ICON_FILE")
    [[ -f "$ICON_FILE" ]] || ICON_FILE=""
fi

if [[ -f "$DESKTOP_FILE" ]]; then
    # Use the top-level name, which may differ from the symlink target name.
    DESKTOP_NAME=$(basename "$(find squashfs-root -maxdepth 1 -name "*.desktop" -print -quit)")
    
    # Prepare the icon
    if [[ -n "$ICON_FILE" ]]; then
        ICON_NAME=$(basename "$ICON_FILE")
        # .DirIcon may resolve to a file without a meaningful name or extension.
        if [[ "$ICON_NAME" == .DirIcon ]]; then
            ICON_NAME="${APP_FILENAME%.*}.png"
        fi
        sudo mkdir -p "$ICON_DEST_DIR"
        sudo cp "$ICON_FILE" "$ICON_DEST_DIR/$ICON_NAME"
        ICON_REF="$ICON_DEST_DIR/$ICON_NAME"
    else
        ICON_REF="application-x-executable"
    fi

    # Patch the desktop file
    # We create a local copy to modify
    cp "$DESKTOP_FILE" "$DESKTOP_NAME"
    
    # Update Exec and Icon lines. 
    # Using @ as delimiter for sed to avoid issues with paths containing slashes.
    sed -i "s@^Exec=.*@Exec=\"$APP_INSTALL_PATH\" %U@" "$DESKTOP_NAME"
    sed -i "s@^Icon=.*@Icon=$ICON_REF@" "$DESKTOP_NAME"
    
    # Install the desktop file
    sudo mkdir -p "$DESKTOP_DIR"
    sudo mv "$DESKTOP_NAME" "$DESKTOP_DIR/$DESKTOP_NAME"
    
    echo "Successfully created menu icon: $DESKTOP_DIR/$DESKTOP_NAME"
else
    echo "Warning: No .desktop file found in AppImage. Menu icon not created."
fi

echo "Installation finished successfully."
