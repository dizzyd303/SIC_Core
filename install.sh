#!/bin/bash
#===============================================================================
# install.sh — SIC Platform Local Installation
# Installs sic_core.sh and module shims to /usr/local/
#
# Usage:
#   sudo ./install.sh
#   ./install.sh --user    (install to ~/.local/)
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
USE_USER=false
[[ "${1:-}" == "--user" ]] && USE_USER=true

if $USE_USER; then
    LIB_DIR="${HOME}/.local/lib"
    BIN_DIR="${HOME}/.local/bin"
    mkdir -p "$LIB_DIR" "$BIN_DIR"
    echo "[*] Installing to user directory: $LIB_DIR and $BIN_DIR"
else
    if [[ $EUID -ne 0 ]]; then
        echo "[!] This script needs root for system-wide install."
        echo "    Use --user for local install, or run with sudo."
        exit 1
    fi
    LIB_DIR="/usr/local/lib"
    BIN_DIR="/usr/local/bin"
    echo "[*] Installing system-wide to $LIB_DIR and $BIN_DIR"
fi

# Install core library
echo "[*] Installing sic_core.sh → $LIB_DIR/"
cp "$SCRIPT_DIR/sic_core.sh" "$LIB_DIR/sic_core.sh"
chmod 644 "$LIB_DIR/sic_core.sh"

# Install module shims
for module in SIC_Security SIC_Skip SIC_Diagnostics SIC_COPE; do
    src="${SCRIPT_DIR}/${module}.sh"
    if [[ -f "$src" ]]; then
        echo "[*] Installing ${module}.sh → $BIN_DIR/"
        cp "$src" "${BIN_DIR}/${module}.sh"
        chmod 755 "${BIN_DIR}/${module}.sh"
    else
        echo "[!] Warning: ${src} not found, skipping"
    fi
done

if $USE_USER; then
    if ! grep -q "$BIN_DIR" "$HOME/.bashrc" 2>/dev/null; then
        echo "" >> "$HOME/.bashrc"
        echo "# SIC Platform" >> "$HOME/.bashrc"
        echo "export PATH=\"\$PATH:$BIN_DIR\"" >> "$HOME/.bashrc"
        echo "[*] Added $BIN_DIR to PATH in ~/.bashrc"
    fi
    echo ""
    echo "[✓] User installation complete."
    echo "    Run: source ~/.bashrc"
    echo "    Or use full path: $BIN_DIR/SIC_Security.sh"
fi

echo ""
echo "Quick start:"
echo "  SIC_Security.sh \"recon example.com for open ports\""
echo "  SIC_Skip.sh \"find social media for johndoe\""
echo "  SIC_Diagnostics.sh \"check vehicle diagnostics\""
echo "  SIC_COPE.sh \"check all microservice health\""
echo ""
echo "With Visa compliance:"
echo "  VISA_MODE=1 H1_USERNAME=spyda573 SIC_Security.sh \"scan visa.com\""
echo ""
echo "Docker:"
echo "  docker compose build"
echo "  docker compose run --rm sic SIC_Security.sh \"recon example.com\""

