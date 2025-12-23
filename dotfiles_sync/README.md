# Dotfiles Sync Script

A **robust, explicit dotfiles synchronization tool** built on top of a **bare Git repository**.
Designed for safety, auditability, and long-term maintenance rather than convenience shortcuts.

This script provides a **single-command workflow** to version-control selected files from `$HOME` without symlinks, duplication, or accidental tracking.

---

## Design Principles

- **Explicit allowlist only**
  Only paths listed in `TRACKED_PATHS` are ever staged.

- **Bare Git repository**
  Git metadata lives in `~/.dotfiles`, not in `$HOME`.

- **Fail-safe defaults**
  No destructive operations, no auto-merges, no silent behavior.

- **Human-readable logging**
  Every run is logged with timestamps and Git output.

- **Idempotent execution**
  Running the script multiple times without changes is safe.

---

## How It Works

- Git repository:
  - **Git dir**: `~/.dotfiles`
  - **Work tree**: `$HOME`

- The script internally runs Git as:

  ```bash
  git --git-dir=$HOME/.dotfiles --work-tree=$HOME
  ```

- Only explicitly listed paths are added and committed.
- The script:
  1. Initializes the repo if missing
  2. Ensures a remote exists (interactive if not)
  3. Previews tracked paths
  4. Stages allowed files
  5. Commits changes (if any)
  6. Pulls safely
  7. Pushes updates
  8. Cleans up and logs results

---

## Directory Layout

```
$HOME
├── .dotfiles/                 # Bare Git repository (auto-created)
├── .local/log/
│   └── dotfilesync.log        # Execution logs
├── .config/
│   └── ...                    # Tracked configs (explicit allowlist)
└── syncdotfiles               # Script (anywhere in PATH)
```

---

## Tracked Paths

Tracked files are defined in the script:

```bash
TRACKED_PATHS=(
  ".config/hypr"
  ".config/waybar"
  ".config/kitty"
  ".config/dunst"
  ".config/tofi"
  ".config/wlogout"
  ".config/qutebrowser"
  ".config/gtk-3.0"
  ".config/gtk-4.0"
  ".config/qt5ct"
  ".config/htop"
  ".config/mpv"
  ".config/vlc"
  ".config/wireplumber"
  ".config/systemd"
  ".config/wallpaper-config"
  ".config/mimeapps.list"
  ".config/QtProject.conf"
  ".config/user-dirs.dirs"
  ".config/user-dirs.locale"
  ".config/.gsd-keyboard.settings-ported"
  ".local/bin"
)
```

- Missing paths are skipped and logged
- Nothing outside this list is ever added

---

## Installation

1. Place the script somewhere in your `PATH`, for example:

```bash
~/.local/bin/syncdotfiles
chmod +x ~/.local/bin/syncdotfiles
```

2. Run it:

```bash
syncdotfiles
```

On first run:

- The bare repository is created automatically
- You will be prompted to add a Git remote if one is not configured

---

## Usage

### Basic Sync

```bash
syncdotfiles
```

This will:

- Show which paths exist and will be synced
- Ask for confirmation
- Commit changes (if any)
- Pull from the remote
- Push updates

---

### Dry Run

```bash
syncdotfiles --dry-run
```

- Shows what would be staged and committed
- Makes **no changes**
- Does not pull or push

---

### Force Mode (Non-interactive)

```bash
syncdotfiles --force
```

- Skips confirmation prompts
- Still fails safely if no remote is configured

Useful for scripted or automated environments.

---

### Cleanup Mode

```bash
syncdotfiles --cleanup
```

- Runs aggressive Git cleanup
- Expires reflogs
- Prunes unreachable objects
- Re-packs repository

This mode is optional and safe to run independently.

---

## Logging

Logs are written to:

```
~/.local/log/dotfilesync.log
```

Features:

- Timestamped entries
- Git command output captured
- Automatic rotation at 10 MB
- Continues gracefully if logging fails

---

## Locking

- A lock file is created at:

  ```
  $XDG_RUNTIME_DIR/dotfilesync.lock
  ```

  (or `/tmp` if unavailable)

- Prevents concurrent runs

- If another instance is running, the script exits cleanly

---

## Git Behavior Guarantees

- No auto-tracking of files
- No recursive `$HOME` adds
- No silent merges
- Pull is explicit and logged
- Commit only happens if there are staged changes

---

## Manual Git Access (Optional)

For inspection or recovery:

```bash
git --git-dir=$HOME/.dotfiles --work-tree=$HOME status
git --git-dir=$HOME/.dotfiles --work-tree=$HOME log --oneline
```

Optional alias:

```bash
alias dotgit='git --git-dir=$HOME/.dotfiles --work-tree=$HOME'
```

---

## Restoring on a New Machine

```bash
git clone --bare <repo-url> ~/.dotfiles
git --git-dir=$HOME/.dotfiles --work-tree=$HOME checkout
```

Then run:

```bash
syncdotfiles
```

---

## What This Script Is Not

- It is **not** a symlink manager
- It is **not** a dotfile generator
- It does **not** auto-discover files
- It does **not** manage secrets

These are intentional design decisions.

---

## Philosophy

This script favors:

- Predictability over automation
- Explicit configuration over heuristics
- Auditability over convenience

It is intended to be boring, reliable, and hard to misuse.

---

**Note:** I have purposefully not included my `~/.config/nvim` dir since it has a seperate repo
