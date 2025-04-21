#!/bin/bash

# Zphisher startup script

ZPHISHER_DIR="$HOME/Zphisher"

echo "[*] Setting up Zphisher..."

# Check if Zphisher folder exists
if [ ! -d "$ZPHISHER_DIR" ]; then
    echo "[+] Cloning Zphisher..."
    git clone https://github.com/htr-tech/zphisher.git "$ZPHISHER_DIR"
fi

cd "$ZPHISHER_DIR"

echo "[*] Setting permissions..."
chmod +x zphisher.sh

echo "[*] Starting Zphisher with Cloudflare in a screen session..."
# Start Zphisher using screen to keep it running in background
screen -dmS zphisher bash -c './zphisher.sh'

echo "[+] Zphisher is running in a screen session. Use 'screen -r zphisher' to attach."