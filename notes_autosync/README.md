# Notes autosync

## Obsidian + Neovim Autosync

**One folder. Versioned. Autosynced to OneDrive (and optionally Raspberry Pi for redundancy). Accessible on Android with Obsidian Mobile.**
This README walks you from zero → fully working setup.

### What you'll get

- **Editing:** Neovim and Obsidian Desktop on the same `~/notes` folder
- **Version control:** local Git commits on every change
- **Autosync:** (near real time)
  - to **OneDrive** via `rclone`
  - to **Raspberry Pi** (over SSH) via `rclone` SFTP (**optional**, pre-commented in script for later use)

- **Manual sync option:** run `syncnotes` to push/pull on demand
- **Android:** local two-way sync + Obsidian Mobile vault
- **Resilient:** systemd user service starts at login; retries on network drops

Works great on Linux Desktop. Notes for MacOS/Windows are at the end.

---

### Prerequisites (Desktop)

```bash
sudo pacman -Syu
sudo pacman -S git rsync inotify-tools
curl -fsSL https://rclone.org/install.sh | sudo bash
```

- git: version history
- inotify-tools: detect changes instantly
- rclone: cloud and SSH/SFTP sync
- rsync: optional alternative for Pi

Create your notes folder:

```bash
mkdir -p ~/notes
cd ~/notes && git init && git add . && git commit -m "Initial commit"
```

---

### OneDrive setup (with rclone)

1. Start config:

   ```bash
   rclone config
   ```

2. Choose: `n` **New Remote** → name it `onedrive`.

3. **Storage:** pick **38) Microsoft OneDrive**

4. Leave `client_id`, `client_secret`, `tenant` empty → **Enter**

5. **Edit Advanced Config?** → `n`

6. **Use web browser to authenticate?** → `y` and log in to your Microsoft account

7. **Type of connection** → `1` (OneDrive Personal or Business)

8. **Select drive you want to use** → pick the entry labeled _OneDrive (personal)_

9. Confirm: `Is this okay?` → `y` → `Keep this remote?` → `y`

Test it:

```bash
rclone lsd onedrive:
```

You should see top-level OneDrive folders. Create the target folder and push the first copy:

```bash
rclone mkdir onedrive:notes
rclone sync ~/notes onedrive:notes
```

If you don’t see `notes` in the OneDrive app, pull to refresh after the first sync.

---

### Raspberry Pi setup (SSH + SFTP via rclone)

_(Optional – skip for now, code is commented in script)_

We’ll sync over **SSH** using `rclone`’s SFTP backend.

**On the Pi:**

```bash
sudo pacman -Syu
sudo pacman -S openssh-server
systemctl enable --now ssh
mkdir -p /home/pi/notes
```

**On your desktop:**

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
ssh-copy-id pi@<PI_HOSTNAME_OR_IP>
ssh pi@<PI_HOSTNAME_OR_IP> 'echo ok; mkdir -p ~/notes'
```

Then create the `pi` remote in rclone:

```bash
rclone config
# n → New remote → name: pi
# Storage: sftp
# host: <PI_HOSTNAME_OR_IP>
# user: pi
# port: (Enter for 22)
# Choose key-based auth → auto-detect ~/.ssh/id_ed25519
# accept defaults → y
```

Test:

```bash
rclone lsd pi:
```

---

### Autosync script (with manual sync support)

Script handles:

- Git add/commit
- `rclone sync` → OneDrive
- _(Optional, commented)_ `rclone sync` → Raspberry Pi
- Debounce so multiple edits get batched
- Prevents overlapping runs (lockfile)
- Manual trigger supported

Create at `~/.local/bin/notes_autosync.sh`:

```bash
mkdir -p ~/.local/bin ~/.local/state/notes-sync
vim ~/.local/bin/notes_autosync.sh
```

Paste:

```bash
#!/usr/bin/env bash
set -euo pipefail

# ====== CONFIG ======
NOTES_DIR="$HOME/notes"
ONEDRIVE_REMOTE="onedrive:notes"
PI_REMOTE="pi:notes"   # Raspberry Pi remote (disabled for now)
DEBOUNCE=5
LOGDIR="$HOME/.local/state/notes-sync"
LOGFILE="$LOGDIR/notes-sync.log"
LOCKFILE="$LOGDIR/sync.lock"
RCLONE_FLAGS=(--fast-list --transfers=8 --checkers=16 --update \
              --exclude ".git/**" --exclude ".obsidian/cache/**")

mkdir -p "$LOGDIR"

log(){ echo "$(date '+%F %T') | $*" | tee -a "$LOGFILE"; }

sync_once(){
  exec 9>"$LOCKFILE" || true
  flock -n 9 || { log "sync already running, skipping"; return 0; }

  log "git commit…"
  ( cd "$NOTES_DIR" && git add -A && git commit -m "Auto backup: $(date '+%F %T')" >/dev/null 2>&1 || true )

  log "rclone → OneDrive"
  rclone sync "$NOTES_DIR" "$ONEDRIVE_REMOTE" "${RCLONE_FLAGS[@]}" | tee -a "$LOGFILE"

  # --- Raspberry Pi sync (uncomment once Pi is ready) ---
  # log "rclone → Raspberry Pi"
  # rclone sync "$NOTES_DIR" "$PI_REMOTE" "${RCLONE_FLAGS[@]}" | tee -a "$LOGFILE"

  log "sync complete"
}

# If manual run requested
if [[ "${1:-}" == "--once" ]]; then
  sync_once
  exit 0
fi

# Initial one-off
sync_once || true

# Debounced watcher
LAST_CHANGE=$(date +%s)
trap 'log "stopping"; exit 0' INT TERM

inotifywait -mrq -e close_write,modify,create,delete,move --format '%w%f' "$NOTES_DIR" | while read -r _
do
  NOW=$(date +%s)
  LAST_CHANGE=$NOW
  if [ ! -f "$LOGDIR/.timer" ]; then
    touch "$LOGDIR/.timer"
    (
      while :; do
        sleep 1
        NOW2=$(date +%s)
        if (( NOW2 - LAST_CHANGE >= DEBOUNCE )); then
          sync_once
          rm -f "$LOGDIR/.timer"
          break
        fi
      done
    ) &
  fi
done
```

Make executable:

```bash
chmod +x ~/.local/bin/notes_autosync.sh
```

---

### Manual sync

Run manually anytime:

```bash
~/.local/bin/notes_autosync.sh --once
```

Add a shell alias for convenience:

```bash
echo 'alias syncnotes="$HOME/.local/bin/notes_autosync.sh --once"' >> ~/.bashrc
source ~/.bashrc
```

Now you can just:

```bash
syncnotes
```

---

### Run at login (systemd user service)

```bash
mkdir -p ~/.config/systemd/user
vim ~/.config/systemd/user/notes_autosync.service
```

Paste:

```ini
[Unit]
Description=Auto-sync notes (OneDrive + Raspberry Pi)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=%h/.local/bin/notes_autosync.sh
Restart=always
RestartSec=10
Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=default.target
```

Enable:

```bash
systemctl --user daemon-reload
systemctl --user enable --now notes_autosync.service
```

---

### Android Setup (Two-way sync + Obsidian Mobile)

1. Install: **Obsidian**, **FolderSync** (or Autosync for OneDrive)
2. Create sync pair:
   - Remote: `/notes` (OneDrive)
   - Local: `/storage/emulated/0/Documents/Notes`
   - Mode: **Two-way**
   - Enable sync on file change
   - Run first sync

3. Open vault in Obsidian Mobile → point to `/storage/emulated/0/Documents/Notes`

---

### Testing checklist

1. **Desktop → OneDrive**

   ```bash
   echo "test $(date)" >> ~/notes/test.md
   rclone ls onedrive:notes | grep test.md
   ```

2. **Desktop → Pi** _(later, once Pi enabled)_

   ```bash
   rclone ls pi:notes | grep test.md
   ```

3. **Phone → Desktop**
   - Edit file in Obsidian Mobile
   - Wait for FolderSync push
   - Confirm update in `git log` on desktop

4. **Manual sync works**

   ```bash
   syncnotes
   ```

---

### Troubleshooting

- No `notes` folder in OneDrive → run `rclone mkdir onedrive:notes`
- Too many syncs → raise `DEBOUNCE` to 10–15
- Conflicts → Obsidian “File Recovery” + Git history
- Pi auth fails → recheck SSH key + remote config
- Service didn’t start → `systemctl --user status notes_autosync.service`

---

### MacOS / Windows notes

- macOS → use `fswatch` instead of `inotify-tools`
- Windows → run inside WSL2

---

### Uninstall

```bash
systemctl --user disable --now notes_autosync.service
rm -f ~/.config/systemd/user/notes_autosync.service
rm -f ~/.local/bin/notes_autosync.sh
```

---
