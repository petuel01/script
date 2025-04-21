#!/bin/bash

# Zphisher auto-setup and startup script

ZPHISHER_DIR="$HOME/Zphisher"

echo "[*] Preparing Zphisher environment..."

if [ -d "$ZPHISHER_DIR" ]; then
    echo "[*] Zphisher folder already exists. Entering directory..."
else
    echo "[+] Zphisher folder not found. Cloning repository..."
    git clone https://github.com/htr-tech/zphisher.git "$ZPHISHER_DIR"
fi

cd "$ZPHISHER_DIR" || { echo "[-] Failed to enter Zphisher directory."; exit 1; }

echo "[*] Setting executable permissions..."
chmod +x zphisher.sh

echo "[*] Launching Zphisher with Cloudflare in a screen session..."
screen -dmS zphisher bash -c './zphisher.sh'

echo "[+] Zphisher is running in a screen session."
echo "[*] Use 'screen -r zphisher' to view it or Ctrl+A then D to detach."
