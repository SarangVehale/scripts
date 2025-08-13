#!/bin/bash
WATCH_DIR="$HOME/notes"
ONEDRIVE_REMOTE="onedrive:notes"
# PI_REMOTE="pi:notes"

inotifywait -m -r -e modify,create,delete,move "$WATCH_DIR" --format '%w%f' |
	while read FILE; do
		# Sync to OneDrive
		rclone sync "$WATCH_DIR" "$ONEDRIVE_REMOTE" --update --copy-links --transfers=4 --checkers=8 --fast-list

		# Sync to Raspberry pi
		# rclone sync "$WATCH_DIR" "$PI_REMOTE" --update --copy-link --transfers=4 --checkers=8 --fast-list

	done
