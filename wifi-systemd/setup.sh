#!/bin/bash

# Wifi Auto-Reconnect with Driver Reset
# Installer Script

set -e

SERVICE_FILE="wifi-loop.service"
SCRIPT_FILE="wifi-loop.sh"
LOGROTATE_FILE="wifi-loop.logrotate"

SCRIPT_DEST="/usr/local/bin/wifi-loop.sh"
SERVICE_DEST="/etc/systemd/system/wifi-loop.service"
LOGROTATE_DEST="/etc/logrotate.d/wifi-loop"

echo "[+] Starting Wi-Fi Auto-Reconnect setup..."

# Check root permission
if [[ $EUID -ne 0 ]]; then
	echo "[-] Please run as root (sudo ./setup.sh)"
	exit 1
fi

# Copy script
echo "[+] Installing main script to $SCRIPT_DEST"
install -Dm755 "SCRIPT_SRC" "$SCRIPT_DEST"

# Copy systemd service
echo "[+] Installing main script to $SERVICE_DEST"
install -Dm644 "SERVICE_SRC" "$SERVICE_DEST"

# Copy script
echo "[+] Installing main script to $LOGROTATE_DEST"
install -Dm644 "$LOGROTATE_SRC" "$LOGROTATE_DEST"

# Reload systemd
echo "[+] Reloading systemd daemon..."
systemctl daemon-reload

# Enable + start service
echo "[+] Enabling and starting wifi-loop.service..."
systemctl enable --now wifi-loop.service

echo "[✓]Setup complete!"
echo "  Check logs: journalctl -u wifi-loop.service -f"
echo "  Flat log:   /var/log/wifi-loop.log"
