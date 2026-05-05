#!/bin/bash

# Script to install an AppImage and create a desktop menu entry.
# Usage: ./install_appimage.sh <path-to-appimage>

set -e

# check if an argument is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <path-to-appimage>"
    exit 1
fi

APPIMAGE_SRC="$1"

# Check if file exists
if [ ! -f "$APPIMAGE_SRC" ]; then
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
# Extract just the .desktop and image files to avoid full extraction if possible
# Note: some AppImages might not support selective extraction easily, 
# but we'll try to find the desktop and icon in the squashfs-root.
"$APP_INSTALL_PATH" --appimage-extract "*.desktop" > /dev/null 2>&1 || true
"$APP_INSTALL_PATH" --appimage-extract "*.png" > /dev/null 2>&1 || true
"$APP_INSTALL_PATH" --appimage-extract "*.svg" > /dev/null 2>&1 || true

# Check if extraction worked
if [ ! -d "squashfs-root" ]; then
    echo "Warning: Could not extract metadata using --appimage-extract. Trying full extraction..."
    "$APP_INSTALL_PATH" --appimage-extract > /dev/null 2>&1
fi

# Find the extracted files
DESKTOP_FILE=$(find squashfs-root -name "*.desktop" -print -quit)
ICON_FILE=$(find squashfs-root \( -name "*.png" -o -name "*.svg" \) -print -quit)

if [ -n "$DESKTOP_FILE" ]; then
    DESKTOP_NAME=$(basename "$DESKTOP_FILE")
    
    # Prepare the icon
    if [ -n "$ICON_FILE" ]; then
        ICON_NAME=$(basename "$ICON_FILE")
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
