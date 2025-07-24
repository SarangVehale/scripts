#!/bin/bash

# ----------------------------
# Input Leap (Barrier) Server Start Script (Fixed)
# ----------------------------

# 📁 Path to your Barrier configuration file
CONFIG_FILE="$HOME/.config/barrier/barrier.conf"

# ✅ Log file
LOG_FILE="$HOME/.local/share/barrier-server.log"

# 🧪 Check if barrier server is already running using full command line matching
if pgrep -f "input-leap-barriers" > /dev/null || pgrep -f "barriers" > /dev/null; then
    echo "$(date): Barrier server already running." >> "$LOG_FILE"
    exit 0
fi

# 🚀 Start the correct binary depending on availability
echo "$(date): Starting Barrier server using $CONFIG_FILE" >> "$LOG_FILE"

if command -v input-leap-barriers &> /dev/null; then
    input-leap-barriers --no-tray --debug INFO --config "$CONFIG_FILE" >> "$LOG_FILE" 2>&1 &
elif command -v barriers &> /dev/null; then
    barriers --no-tray --debug INFO --config "$CONFIG_FILE" >> "$LOG_FILE" 2>&1 &
else
    echo "Error: Neither input-leap-barriers nor barriers found in PATH." >> "$LOG_FILE"
    exit 1
fi

exit 0

