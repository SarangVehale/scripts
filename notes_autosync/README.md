# Notes Autosync

## Obsidian + Neovim Autosync

**One folder. Versioned. Autosynced to Onedrive and a Raspberry Pi (for redundancy). Accessible on Android with Obsidian Mobile.**
This README walks you from zero -> fully working setup.

### What you'll get

- **Editing:** Neovim and Obsidian Desktop on the same `~/notes` folder
- **Version control:** local Git commits on every change
- **Autosync:**(near real time)
  - to **OneDrive** via `rclone`.
  - to **Rasberry pi** (over SSH) via `rclone` SFTP(alt: `rsync`)
- **Android:** local two-way sync+Obsidian Mobile vault
- **Resilient:** systemd user service starts at login; retries on network drops.

Works great on Linux Desktop. Notes for MacOS/Windows are at the end.

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

Create your notes folder

```bash
mkdir -p ~/notes
cd ~/notes && git init && git add . && git commit -m "Initial commit"
```

### OneDrive setup(with rclone)

1. Start config:

   ```bash
   rclone config
   ```

2. Choos: `n` **New Remote** -> name it `onedrive`.
3. **Storage:** pick **38) Microsoft OneDrive**
4. Leave `client_id`, `client_secret`, `tenant` empty -> **Enter**
5. **Edit Advanced Config?** -> `n`
6. **Use web browser to authenticate?** -> `y` and log in to your Microsoft account.
7. **Type of connection** -> `1`(OneDrive Personal or Business)
8. **Select drive you want to use** -> Choose the entry named `OneDrive(personal)`
9. Confirm: `Is this okay?` -> `y` -> `Keep this remote?` -> `y`

Test it:

```bash
rclone lsd onedrive:
```

You should see top-level Onedrive folders. Create the target folder and push the first copy:

```bash
rclone mkdir onedrive:notes
rclone sync ~/notes onedrive:notes
```

If you don't see `notes` in the mobile app, pull to refresh after the first sync.

### Raspberry Pi setup (SSH + SFTP via `rclone`)

We'll sync over **SSH** using `rclone`'s a SFTP backend. It's simple and secure

**On the PI**

```bash
sudo pacman -Syu
sudo pacman -S openssh-server
systemctl enable --now ssh
mkdir -p /home/pi/notes
```

**On your desktop: SSH keys**

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
ssh-copy-id pi@<PI_HOSTNAME_OR_IP>
# sanity check
ssh pi@<PI_HOSTNAME_OR_IP> 'echo ok; mkdir -p ~/notes'
```

\*\*Create the `pi` remote in rclone(SFTP)

```bash
rclone config
# nj New remote -> name:pi
# Storage: sftp
# host: <PI_HOSTNAME_OR_IP>
# user: pi
# port: (Enter for 22)
# Choose key-based auth -> auto-detect your ~/.ssh/id_ed255
# accept default, then y to save
```

Test:

```bash
rclone lsd pi:
# Expect to see your home directories, or use explicit path with pi:notes
```

> Alternatively (not required), direct `rsync` over SSH works too. See Appendix A.

### Autosync script (debounced, dual-target, safe)

This script watches `~/notes` and, after a short debounce, does:

- Git add/commit
- `rclone sync` -> Onedrive
- `rclone sync` -> Raspberry Pi
- Skips `.git/` and Obsidian's cache for speed
- Prevents overlapping runs(lockfile)

Create the script at `~/.local/bin/notes_autosync.sh`:

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
PI_REMOTE="pi:notes"          # or pi:/home/pi/notes
DEBOUNCE=5                     # seconds to wait after last change
LOGDIR="$HOME/.local/state/notes-sync"
LOGFILE="$LOGDIR/notes-sync.log"
LOCKFILE="$LOGDIR/sync.lock"
RCLONE_FLAGS=(--fast-list --transfers=8 --checkers=16 --update \
              --exclude ".git/**" --exclude ".obsidian/cache/**")

mkdir -p "$LOGDIR"

log(){ echo "$(date '+%F %T') | $*" | tee -a "$LOGFILE"; }

sync_once(){
  # Prevent concurrent syncs
  exec 9>"$LOCKFILE" || true
  flock -n 9 || { log "sync already running, skipping"; return 0; }

  log "git commit…"
  ( cd "$NOTES_DIR" && git add -A && git commit -m "Auto backup: $(date '+%F %T')" >/dev/null 2>&1 || true )

  log "rclone → OneDrive"
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

inotifywait -mrq -e close_write,modify,create,delete,move --format '%w%f' "$NOTES_DIR" | while read -r _
do
  NOW=$(date +%s)
  LAST_CHANGE=$NOW
  # Run a debounced sync in the background if not already queued
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

Make it executable:

```bash
chmod +x ~/.local/bin/notes_autosync.sh
```

> Tip: change `DEBOUNCE` to `2`-`10` seconds to taste. Lower = more frequent cloud pushes.

### Run at login (systemd user service)

Create service file:

```bash
mkdir -p ~/.config/systemd/user
vim ~/.config/systemd/user/notes_autosync.service
```

Paste:

```bash
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

Enable + Start :

```bash
systemctl --user daemon-reload
systemctl --user enable --now notes_autosync.service
```

Optional: Keep running even without active GUI login:

```bash
loginctl enable-linger "$USER"
```

Status & logs:

```bash
systemctl --user status notes_autosync.service
journalctl --user -u ntoes_autosync.service -f
```

### Android Setup (Two-way sync + Obsidian Mobile)

**Goal:** Keep a local copy of your vault on Android for fast, offline editing in Obsidian Mobile, mirrored to OneDrive

1. **Install Apps**
   - Obsidian
   - FolderSync (Lite is fine) or Autosync for Onedrive (MetaCtrl)
   - (Optional): A Markdown editor like `Markor` if you prefer.

2. Create the phone <-> OneDrive sync pair
   - Using **FolderSync** (steps are similar in Autosync):
     1. Add **Account -> Microsoft OneDrive -> signin**
     2. **Create Sync -> Two way**
     3. Remote folder: `/notes`
     4. Local folder: `/storage/emulated/0/Documents/Notes` (or your choice)
     5. Options -> enable **Sync on file change** (near real-time) -> background sync
     6. Run one **manual sync** to pull existing notes.

3. Open the vault in Obsidian Mobile
   1. Open Obsidian -> **Open folder as vault**
   2. Pick `/storage/emulated/0/Documents/Notes`
   3. Install plugins you like (Tasks, Calendar, etc.)

   > Phone edits -> OneDrive -> Desktop (picked up by your autosync). Desktop edits -> OneDrive -> Phone(FolderSync watches and pulls)

### Obsidian + Neovim tips:

- In Neovim, consider:
  - `epwalsh/obsidian.nvim` or `renerocksai/telekasten.nvim`
  - `iamcco/mardown-preview.nvim` or terminal `glow` for previews

- In Obsidian Deskop:
  - Open `~/notes` as vault.
  - Enable Daily Notes, Templates and any plugins you prefer.

### Testing checklist

1. Desktop -> OneDrive

   ```bash
   echo "test $(date)" >> ~/notes/hello.md
   # within a few seconds
   rclone ls onedrive:notes | grep hello.md
   ```

2. Desktop -> Pi

   ```bash
   rclone ls pi:notes | grep hello.md
   ```

3. Phone -> Desktop
   - Edit a note in Obsidian Mobile -> wait for FolderSync push
   - Confirm file updated locally on desktop and committed in `git log`

### Troubleshooting

- I don’t see notes in OneDrive app
  - Run once: `rclone mkdir onedrive:notes && rclone sync ~/notes onedrive:notes`

- Script too chatty / too frequent
  - Increase `DEBOUNCE` to 10–15 seconds

- Avoid syncing caches
  - Add more excludes to `RCLONE_FLAGS`, e.g. `--exclude "node_modules/**`"

- Permission denied on Pi
  - Ensure the pi user owns /home/pi/notes and you copied your SSH key

- Service didn’t start
  - Check `systemctl --user status notes_autosync.service`

- Conflict resolution
  - Rclone uses timestamps/size by default. If you often edit on multiple devices simultaneously, consider enabling Obsidian’s “File recovery” plugin and keep Git history for safety.

### Optional: use `rsync` instead of `rclone` for the Pi

If you prefer pure `rsync` over SSH, replace the Pi step in the script with:

```bash
rsync -az --delete --exclude .git/ --exclude .obsidian/cache/ "$NOTES_DIR/" pi@<PI_HOSTNAME_OR_IP>:/home/pi/notes/
```

Pros: ubiquitos, very fast on LAN. Cons: one more tool to manage

### MacOS and Windows notes

> Cry about it ...

- macOS: replace `inotify-tools` with `fswatch` and adjust the watcher line, or use launchd. `rclone`, `git` and the rest are the same (via Homebrew).
- Windows: best done inside **WSL** so you can use `inotifywait` and `systemd --user` (WSLg w/ systemd on recent Ubuntu).

### Uninstall / disable

```bash
systemctl --user disable --now notes_autosync.service
rm -f ~/.config/systemd/user/notes_autosync.service
rm -f ~/.local/bin/notes_autosync.sh
```

### FAQs

**Q: Will this sync while a file is still open in Neovim?**
-> Yes. The watcher triggers on every write/modify/close event. Your changes are captured after each write (:w), and the debounce bundles rapid edits.

**Q: Do I still need Git if I have cloud + Pi?**
-> Highly recommended. Git gives you real history and easy rollbacks; cloud/Pi are storage targets.

**Q: Can I encrypt sensitive notes?**
-> Yes. Consider age or gocryptfs. Rclone also supports encrypted remotes.

**Q: What about Obsidian Sync?**
-> It works great, but this guide keeps you self‑hosted/cloud‑agnostic and free.
