#!/bin/bash

# ══════════════════════════════════════════════════════════════
#  Host-side Test Script for Ryujinx
# ══════════════════════════════════════════════════════════════

# 1. Configuration (UPDATE THESE PATHS)
# Path to your Ryujinx executable
RYUJINX_BIN="Ryujinx" 
# Ryujinx data folder (usually ~/.config/Ryujinx on Linux)
RYU_DATA_DIR="$HOME/.config/Ryujinx"
# Virtual SD Card path
SD_ROOT="${RYU_DATA_DIR}/sdcard"

# 2. Setup Paths
NRO_SOURCE="./build-switch/mkxpz.nro"
DEST_DIR="${SD_ROOT}/switch/mkxp-z"
LOG_FILE="${SD_ROOT}/mkxpz_log.txt"

# 3. Check for Game Data
# The emulator needs the actual game files (Game.ini, Data, etc) 
# to be present in the destination folder, or it will just exit.
if [ ! -f "${DEST_DIR}/Game.ini" ] && [ ! -f "${DEST_DIR}/Game.rgssad" ]; then
    echo "⚠️  WARNING: No Game Data found in ${DEST_DIR}"
    echo "   Please copy your RPG Maker game files (Game.ini, Data/, etc.)"
    echo "   into: ${DEST_DIR}"
    echo "   before running this script."
    mkdir -p "${DEST_DIR}"
    exit 1
fi

# 4. Deploy NRO
echo "📦 Deploying mkxpz.nro to Emulator SD Card..."
mkdir -p "${DEST_DIR}"
cp "${NRO_SOURCE}" "${DEST_DIR}/mkxpz.nro"

# 5. Clear old log
# We truncate the log file on the host so 'tail' starts fresh
echo "" > "${LOG_FILE}"

# 6. Launch Ryujinx in background
echo "🚀 Launching Ryujinx..."
# Using setsid/nohup ensures Ryujinx doesn't die if we kill the script
# We point it directly to the NRO file to auto-boot it
nohup "$RYUJINX_BIN" "${DEST_DIR}/mkxpz.nro" >/dev/null 2>&1 &
RYU_PID=$!

echo "👀 Tailing log file (Ctrl+C to stop watching)..."
echo "────────────────────────────────────────────────"

# 7. Tail the log file
# -F keeps trying to open the file if it disappears/reappears
tail -F -n 0 "${LOG_FILE}"

# Optional: Kill Ryujinx when you Ctrl+C the script
# kill $RYU_PID
