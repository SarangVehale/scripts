#!/usr/bin/env bash
set -euo pipefail

# ====== CONFIG ======
NOTES_DIR="$HOME/notes"
ONEDRIVE_REMOTE="onedrive:notes"
PI_REMOTE="pi:notes" # or pi:/home/pi/notes
DEBOUNCE=5           # seconds to wait after last change
LOGDIR="$HOME/.local/state/notes-sync"
LOGFILE="$LOGDIR/notes-sync.log"
LOCKFILE="$LOGDIR/sync.lock"
RCLONE_FLAGS=(--fast-list --transfers=8 --checkers=16 --update
	--exclude ".git/**" --exclude ".obsidian/cache/**")

mkdir -p "$LOGDIR"

log() { echo "$(date '+%F %T') | $*" | tee -a "$LOGFILE"; }

sync_once() {
	# Prevent concurrent syncs
	exec 9>"$LOCKFILE" || true
	flock -n 9 || {
		log "sync already running, skipping"
		return 0
	}

	log "rclone ← OneDrive (pull updates)"
	# Copy new/updated files from OneDrive → local
	rclone copy "$ONEDRIVE_REMOTE" "$NOTES_DIR" "${RCLONE_FLAGS[@]}" | tee -a "$LOGFILE"

	log "git commit…"
	(cd "$NOTES_DIR" && git add -A && git commit -m "Auto backup: $(date '+%F %T')" >/dev/null 2>&1 || true)

	log "rclone → OneDrive (push back)"
	# Push everything local → OneDrive (keeps it in sync)
	rclone sync "$NOTES_DIR" "$ONEDRIVE_REMOTE" "${RCLONE_FLAGS[@]}" | tee -a "$LOGFILE"

	log "rclone → RaspberryPi"
	rclone sync "$NOTES_DIR" "$PI_REMOTE" "${RCLONE_FLAGS[@]}" | tee -a "$LOGFILE"

	log "sync complete"
}

# Initial one-off to ensure destinations exist
sync_once || true

# Debounced watcher
LAST_CHANGE=$(date +%s)
trap 'log "stopping"; exit 0' INT TERM

inotifywait -mrq -e close_write,modify,create,delete,move --format '%w%f' "$NOTES_DIR" | while read -r _; do
	NOW=$(date +%s)
	LAST_CHANGE=$NOW
	# Run a debounced sync in the background if not already queued
	if [ ! -f "$LOGDIR/.timer" ]; then
		touch "$LOGDIR/.timer"
		(
			while :; do
				sleep 1
				NOW2=$(date +%s)
				if ((NOW2 - LAST_CHANGE >= DEBOUNCE)); then
					sync_once
					rm -f "$LOGDIR/.timer"
					break
				fi
			done
		) &
	fi
done
