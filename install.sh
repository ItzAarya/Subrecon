#!/bin/bash
#
# install.sh - Installs required recon tools (if missing), then installs
# subrecon.sh into ~/bin and ensures it's on PATH.
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

# ---- Install dependencies ----
# Most of these are packaged in Kali's apt repos; assetfinder generally is not,
# so it falls back to 'go install' if apt doesn't have it and Go is available.
install_apt() {
    local pkg="$1"
    echo "[*] Installing $pkg via apt..."
    sudo apt-get install -y "$pkg"
}

install_go() {
    local name="$1" import_path="$2"
    if ! command -v go &>/dev/null; then
        echo "[!] Go is not installed, cannot install $name via 'go install'."
        echo "    Install Go first (sudo apt-get install -y golang-go), then re-run this script."
        return 1
    fi
    echo "[*] Installing $name via 'go install'..."
    go install "$import_path@latest"
    # Make sure $GOPATH/bin (or default ~/go/bin) is on PATH for later steps
    GOBIN_DIR="$(go env GOPATH 2>/dev/null)/bin"
    export PATH="$GOBIN_DIR:$PATH"
}

NEED_APT_UPDATE=1
ensure_apt_updated() {
    if [ "$NEED_APT_UPDATE" -eq 1 ]; then
        echo "[*] Running apt-get update..."
        sudo apt-get update
        NEED_APT_UPDATE=0
    fi
}

echo "[*] Checking dependencies: assetfinder, subfinder, findomain, amass, httpx, gowitness, subzy, nuclei"
echo

if ! command -v assetfinder &>/dev/null; then
    install_go "assetfinder" "github.com/tomnomnom/assetfinder" || true
else
    echo "[+] assetfinder already installed."
fi

if ! command -v subfinder &>/dev/null; then
    ensure_apt_updated
    install_apt subfinder || install_go "subfinder" "github.com/projectdiscovery/subfinder/v2/cmd/subfinder" || true
else
    echo "[+] subfinder already installed."
fi

if ! command -v findomain &>/dev/null; then
    ensure_apt_updated
    install_apt findomain || true
else
    echo "[+] findomain already installed."
fi

if ! command -v amass &>/dev/null; then
    ensure_apt_updated
    install_apt amass || true
else
    echo "[+] amass already installed."
fi

# httpx: Kali's apt package is named 'httpx-toolkit' (there's already an unrelated
# 'httpx' package in Debian/Kali repos), and it installs a binary called
# 'httpx-toolkit' rather than 'httpx'. We symlink it so subrecon.sh's plain
# 'httpx' calls work either way.
if ! command -v httpx &>/dev/null; then
    ensure_apt_updated
    if install_apt httpx-toolkit; then
        if command -v httpx-toolkit &>/dev/null && ! command -v httpx &>/dev/null; then
            mkdir -p "$TARGET_DIR"
            ln -sf "$(command -v httpx-toolkit)" "$TARGET_DIR/httpx"
            echo "[+] Symlinked httpx -> httpx-toolkit in $TARGET_DIR"
        fi
    else
        install_go "httpx" "github.com/projectdiscovery/httpx/cmd/httpx" || true
    fi
else
    echo "[+] httpx already installed."
fi

if ! command -v gowitness &>/dev/null; then
    ensure_apt_updated
    install_apt gowitness || install_go "gowitness" "github.com/sensepost/gowitness" || true
else
    echo "[+] gowitness already installed."
fi

if ! command -v subzy &>/dev/null; then
    install_go "subzy" "github.com/PentestPad/subzy" || true
else
    echo "[+] subzy already installed."
fi

if ! command -v nuclei &>/dev/null; then
    ensure_apt_updated
    install_apt nuclei || install_go "nuclei" "github.com/projectdiscovery/nuclei/v3/cmd/nuclei" || true
else
    echo "[+] nuclei already installed."
fi

echo
echo "[*] Updating nuclei templates (safe to re-run anytime)..."
if command -v nuclei &>/dev/null; then
    nuclei -update-templates || echo "[!] Could not update nuclei templates, continuing anyway."
else
    echo "[!] nuclei not found, skipping template update."
fi

echo
MISSING_DEPS=0
for tool in assetfinder subfinder findomain amass httpx gowitness subzy nuclei; do
    if ! command -v "$tool" &>/dev/null; then
        echo "[!] $tool is still not installed. subrecon.sh will skip that stage until it's available."
        MISSING_DEPS=1
    fi
done
if [ "$MISSING_DEPS" -eq 0 ]; then
    echo "[+] All dependencies are installed."
fi
echo

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

# Persist Go's bin directory to PATH too, in case anything was installed via 'go install'
if command -v go &>/dev/null; then
    GOBIN_DIR="$(go env GOPATH 2>/dev/null)/bin"
    if [ -d "$GOBIN_DIR" ] && ! echo "$PATH" | tr ':' '\n' | grep -qx "$GOBIN_DIR"; then
        if ! grep -qF "$GOBIN_DIR" "$RC_FILE" 2>/dev/null; then
            echo "export PATH=\"$GOBIN_DIR:\$PATH\"" >> "$RC_FILE"
            echo "[+] Added $GOBIN_DIR to PATH in $RC_FILE"
        fi
    fi
fi

echo "[+] Done. Try: subrecon.sh example.com"
