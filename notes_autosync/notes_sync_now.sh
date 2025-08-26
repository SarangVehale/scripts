#!/usr/bin/env bash
set -euo pipefail

NOTES_DIR="$HOME/notes"
ONEDRIVE_REMOTE="onedrive:notes"
# PI_REMOTE="pi:notes"   # keep for later

LOGDIR="$HOME/.local/state/notes-sync"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/manual-sync.log"

RCLONE_FLAGS=(--fast-list --transfers=8 --checkers=16 --update
	--exclude ".git/**" --exclude ".obsidian/cache/**")

log() { echo "$(date '+%F %T') | $*" | tee -a "$LOGFILE"; }

log "=== Manual sync started ==="

# 1. Commit local changes
log "git commit..."
(cd "$NOTES_DIR" && git add -A && git commit -m "Manual sync: $(date '+%F %T')" >/dev/null 2>&1 || true)

# 2. Push → OneDrive
log "rclone push → OneDrive"
rclone sync "$NOTES_DIR" "$ONEDRIVE_REMOTE" "${RCLONE_FLAGS[@]}" | tee -a "$LOGFILE"

# 3. (Later) Push → Pi
# log "rclone push → Raspberry Pi"
# rclone sync "$NOTES_DIR" "$PI_REMOTE" "${RCLONE_FLAGS[@]}" | tee -a "$LOGFILE"

# 4. Pull ← OneDrive
log "rclone pull ← OneDrive"
rclone sync "$ONEDRIVE_REMOTE" "$NOTES_DIR" "${RCLONE_FLAGS[@]}" | tee -a "$LOGFILE"

log "=== Manual sync complete ==="
