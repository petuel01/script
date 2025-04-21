#!/bin/bash
# ------------------------------------
# zeustech — Zphisher Auto‑Setup Script
# ------------------------------------

ZPHISHER_DIR="$HOME/Zphisher"

echo "==========================================="
echo "       zeustech Zphisher Startup           "
echo "==========================================="

# 1. Clone if needed, or just cd in
if [ -d "$ZPHISHER_DIR" ]; then
    echo "[*] Found existing Zphisher directory. Entering it..."
else
    echo "[+] Zphisher not found — cloning from GitHub..."
    git clone https://github.com/htr-tech/zphisher.git "$ZPHISHER_DIR"
fi

cd "$ZPHISHER_DIR" || { echo "[-] Cannot enter $ZPHISHER_DIR"; exit 1; }

# 2. Ensure the main script is executable
echo "[*] Setting permissions on zphisher.sh..."
chmod +x zphisher.sh

# 3. Print your mark
echo
echo "=== zeustech ==="
echo

# 4. Launch Zphisher interactively (ends here at menu)
bash zphisher.sh