#!/bin/bash

# Wifi Auto-Reconnect Uninstall Script
# Removes script, service, and logrotate config

set -e

SCRIPT_DEST="/usr/local/bin/wifi-loop.sh"
SERVICE_DEST="/etc/systemd/system/wifi-loop.service"
LOGROTATE_DEST="/etc/logrotate.d/wifi-loop"
LOG_FILE="/var/log/wifi-loop.log"

echo "[+] Starting Wifi Auto-Reconnect uninstall..."

# Check root permission
if [[ $EUID -ne 0 ]]; then
	echo "[-] Please run as root (sudo ./uninstall.sh)"
	exit 1
fi

# Stop + disable systemd service
if systemctl is-enabled --quiet wifi-loop.service; then
	echo "[+] Disabling service..."
	systemctl disable --now wifi-loop.service
fi

# Remove installed files
echo "[+] Removing installed files..."
rm -f "$SCRIPT_DEST"
rm -f "$SERVICE_DEST"
rm -f "$LOGROTATE_DEST"

# Reload systemd
echo "[+] Reloading systemd daemon"
systemctl daemon-reload

# Remove logs (optional)
if [ -f "$LOG_FILE" ]; then
	echo "[+] Removing old log files..."
	rm -f "$LOG_FILE"
fi

echo "[✓] Uninstall complete!"
