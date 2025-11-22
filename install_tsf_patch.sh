#!/bin/bash
#
# Install TSF Sync Patch to Morse Driver
#
# This script installs the TSF sync patch into the morse_driver package
# after feeds have been updated.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_SOURCE="$SCRIPT_DIR/patches/morse_driver/999-tsf-sync.patch"
PATCH_DEST="$SCRIPT_DIR/feeds/morse/essentials/morse_driver/patches/999-tsf-sync.patch"

echo "=== Morse Driver TSF Sync Patch Installer ==="
echo

# Check if morse feed exists
if [ ! -d "$SCRIPT_DIR/feeds/morse" ]; then
    echo "ERROR: morse feed not found at $SCRIPT_DIR/feeds/morse"
    echo "Please run './scripts/feeds update morse' first"
    exit 1
fi

# Check if source patch exists
if [ ! -f "$PATCH_SOURCE" ]; then
    echo "ERROR: Source patch not found at $PATCH_SOURCE"
    exit 1
fi

# Create destination directory
mkdir -p "$(dirname "$PATCH_DEST")"

# Copy patch
echo "Installing TSF sync patch..."
cp "$PATCH_SOURCE" "$PATCH_DEST"

# Verify
if [ -f "$PATCH_DEST" ]; then
    echo "✓ Patch installed successfully!"
    echo
    echo "Location: $PATCH_DEST"
    echo
    echo "The patch will be automatically applied during the build."
    echo
    echo "Next steps:"
    echo "  1. ./scripts/morse_setup.sh -i -b <board>"
    echo "  2. make package/feeds/morse/morse_driver/compile V=s"
else
    echo "ERROR: Failed to install patch"
    exit 1
fi
