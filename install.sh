#!/bin/bash
#
# install.sh - Installs subrecon.sh into ~/bin and ensures it's on PATH.
#
# Usage: ./install.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO_DIR/bin/subrecon.sh"
TARGET_DIR="$HOME/bin"
TARGET="$TARGET_DIR/subrecon.sh"

if [ ! -f "$SRC" ]; then
    echo "[!] Could not find $SRC. Run this script from inside the cloned repo."
    exit 1
fi

mkdir -p "$TARGET_DIR"
cp "$SRC" "$TARGET"
chmod +x "$TARGET"

echo "[+] Installed subrecon.sh to $TARGET"

# Detect shell rc file
SHELL_NAME="$(basename "${SHELL:-bash}")"
case "$SHELL_NAME" in
    zsh) RC_FILE="$HOME/.zshrc" ;;
    bash) RC_FILE="$HOME/.bashrc" ;;
    *) RC_FILE="$HOME/.bashrc" ;;
esac

# Add ~/bin to PATH if not already present
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$TARGET_DIR"; then
    if ! grep -qF "$TARGET_DIR" "$RC_FILE" 2>/dev/null; then
        echo "export PATH=\"$TARGET_DIR:\$PATH\"" >> "$RC_FILE"
        echo "[+] Added $TARGET_DIR to PATH in $RC_FILE"
    fi
    echo "[*] Run 'source $RC_FILE' or restart your terminal to use 'subrecon.sh' from anywhere."
else
    echo "[+] $TARGET_DIR is already in your PATH."
fi

echo "[+] Done. Try: subrecon.sh example.com"
