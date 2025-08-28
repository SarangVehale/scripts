#!/bin/bash

DEVICE="wlan0"
PING_TARGET="8.8.8.8"
FAIL_COUNT=0
MAX_FAILS=5      # Max failed attempts before reloading driver
DRIVER="mt7921e" # you can change this according to your wifi driver

log() {
	MSG="$1"
	echo "$(date): $MSG" | tee -a /var/log/wifi-loop.log
	logger -t wifi-loop "$MSG"
}

while true; do
	# check if device is connect according to NetworkManager
	STATE=$(nmcli -t -f GENERAL.STATE device show "$DEVICE" 2>/dev/null | cut -d: -f2)

	if [ "$STATE" -ne 100 ]; then
		log "$DEVICE disconnected, trying to reconnect..."
		nmcli device connect "$DEVICE"
		((FAIL_COUNT++))

	else
		# Extra check: internet connectivtiy
		if ! ping -c1 -W2 $PING_TARGET >/dev/null 2>&1; then
			log "$DEVICE connected but no internet, restarting ..."
			nmcli device disconnect "$DEVICE"
			((FAIL_COUNT++))
		else
			log "$DEVICE OK"
			FAIL_COUNT=0
		fi
	fi

	# IF too many failures, reload driver
	if [ "$FAIL_COUNT" -ge "$MAX_FAILS" ]; then
		log "Too many failures, reloading driver $DRIVER ..."
		nmcli device disconnect "$DEVICE"
		sudo modprobe -r "$DRIVER"
		sleep 2
		sudo modprobe "$DRIVER"
		sleep 5
		nmcli device connect "$DEVICE"
		FAIL_COUNT=0
	fi

	sleep 20

done
