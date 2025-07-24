#!/bin/bash

# =======================================================
# Arch Linux Backup Script (Interactive, Portable)
# Author: Sarang vehale
# Description:
#   Creates a compressed, symlink-safe, reproducible backup
#   of dotfiles, configs, important dirs, packages, secrets.
#   Supports export to USB, .tar.zst, scp, or rclone.
# =======================================================

set -euo pipefail

# -------------------------------------------------------
# Helper: install tool on demand
# -------------------------------------------------------
require_tool() {
	local tool="$1"
	if ! command -v "$tool" &>/dev/null; then
		echo "[*] Installing missing tool: $tool"
		sudo pacman -S --needed --noconfirm "$tool"
	fi
}

# -------------------------------------------------------
# Configuration
# -------------------------------------------------------
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_DIR="$HOME/arch_backup_$TIMESTAMP"
INSTALLER_PATH="$HOME/Development/scripts/backup/install.sh" # Modify if install.sh is elsewhere

# DOTFILES=(
#     .bashrc .zshrc .vimrc .tmux.conf .xinitrc .profile .gitconfig
#     .config/kitty .config/nvim .config/waybar .config/wlogout .config/hypr
#     .local/bin .fonts .themes .icons
# )

DOTFILES=(
	.bashrc .zshrc .vimrc .tmux.conf .xinitrc .profile .gitconfig
	.config/ .local/bin .fonts .themes .icons
)

BROWSER_DIRS=(
	"$HOME/.mozilla"
	"$HOME/.config/qutebrowser"
	"$HOME/.zen"
	"$HOME/.config/google-chrome"
)

IMP_DIRS=(
	"$HOME/Pictures/wallpapers"
	"$HOME/Development"
	"$HOME/notes"
	"$HOME/Downloads"
)

mkdir -p "$BACKUP_DIR/pkglist"

# -------------------------------------------------------
# Helper: tarball creator
# -------------------------------------------------------
create_tarball() {
	local archive_name="$1"
	shift
	local items=("$@")
	tar --zstd -cf "$BACKUP_DIR/$archive_name.tar.zst" --ignore-failed-read \
		--exclude=".cache" --exclude="Trash" \
		-C "$HOME" "${items[@]}"
	echo "[+] Created $archive_name.tar.zst"
}

# -------------------------------------------------------
# Step 1: Create Backups
# -------------------------------------------------------

echo "[*] Creating dotfiles archive..."
create_tarball "dotfiles" "${DOTFILES[@]}"

echo "[*] Creating browser configs archive..."
temp_browser_list=()
for browser in "${BROWSER_DIRS[@]}"; do
	[[ -d "$browser" ]] && temp_browser_list+=("${browser#$HOME/}") || echo "[!] Skipped: $browser"
done
[[ ${#temp_browser_list[@]} -gt 0 ]] && create_tarball "browsers" "${temp_browser_list[@]}"

echo "[*] Creating important dirs archive..."
temp_imp_list=()
for dir in "${IMP_DIRS[@]}"; do
	[[ -d "$dir" ]] && temp_imp_list+=("${dir#$HOME/}") || echo "[!] Skipped: $dir"
done
[[ ${#temp_imp_list[@]} -gt 0 ]] && create_tarball "imp_dirs" "${temp_imp_list[@]}"

echo "[*] Creating secrets archive (.ssh, .gnupg)..."
create_tarball "secrets" ".ssh" ".gnupg"

# -------------------------------------------------------
# Step 2: Save Package Lists
# -------------------------------------------------------
echo "[*] Saving package list..."
pacman -Qqen >"$BACKUP_DIR/pkglist/official.txt"
pacman -Qqem >"$BACKUP_DIR/pkglist/aur.txt"
require_tool zstd
zstd "$BACKUP_DIR/pkglist/official.txt" --rm
zstd "$BACKUP_DIR/pkglist/aur.txt" --rm

# -------------------------------------------------------
# Step 3: Copy install.sh if available
# -------------------------------------------------------
if [[ -f "$INSTALLER_PATH" ]]; then
	cp "$INSTALLER_PATH" "$BACKUP_DIR/install.sh"
	echo "[*] install.sh copied into backup"
else
	echo "[!] install.sh not found at $INSTALLER_PATH"
fi

# -------------------------------------------------------
# Step 4: Generate manifest
# -------------------------------------------------------
echo "[*] Generating manifest of backup contents..."
if command -v tree &>/dev/null; then
	require_tool tree
	tree "$BACKUP_DIR" >"$BACKUP_DIR/MANIFEST.txt"
else
	find "$BACKUP_DIR" -maxdepth 2 >"$BACKUP_DIR/MANIFEST.txt"
fi

# -------------------------------------------------------
# Step 5: Shipping options (interactive)
# -------------------------------------------------------
echo
echo "==================================================="
echo "Backup complete: $BACKUP_DIR"
echo "==================================================="
echo
echo "[*] Choose an export method:"
select option in \
	"Copy to external drive (USB)" \
	"Compress into single .tar.zst archive" \
	"Upload to remote machine (scp)" \
	"Upload to cloud remote (rclone)" \
	"Skip (do nothing)"; do

	case $REPLY in

	1)
		require_tool rsync
		echo
		echo "[*] Listing mounted external drives:"
		lsblk -o NAME,MOUNTPOINT,SIZE,FSTYPE,LABEL | grep -E '/run/media|/media' || echo "  (no USB mountpoints detected)"
		echo
		read -rp "Enter full path to mounted external drive (e.g., /run/media/$USER/MyDrive): " DRIVE_PATH
		if [[ -d "$DRIVE_PATH" ]]; then
			rsync -avh "$BACKUP_DIR" "$DRIVE_PATH/"
			echo "[✔] Backup copied to $DRIVE_PATH"
		else
			echo "[!] Invalid path: $DRIVE_PATH"
		fi
		break
		;;

	2)
		require_tool zstd
		ARCHIVE_NAME="${BACKUP_DIR##*/}.tar.zst"
		echo "[*] Compressing to $ARCHIVE_NAME..."
		tar -cf "$ARCHIVE_NAME" -I zstd -C "$(dirname "$BACKUP_DIR")" "$(basename "$BACKUP_DIR")"
		echo "[✔] Created archive: $ARCHIVE_NAME"
		break
		;;

	3)
		require_tool openssh
		echo
		echo "[*] Upload to remote machine using SCP"
		read -rp "Enter remote login (e.g., user@hostname): " SCP_TARGET
		read -rp "Enter full remote path (e.g., /home/user/backups/): " SCP_PATH
		if [[ -n "$SCP_TARGET" && -n "$SCP_PATH" ]]; then
			scp -r "$BACKUP_DIR" "$SCP_TARGET:$SCP_PATH"
			echo "[✔] Backup uploaded to $SCP_TARGET:$SCP_PATH"
		else
			echo "[!] Invalid SCP input"
		fi
		break
		;;

	4)
		require_tool rclone
		echo
		echo "[*] Upload to cloud remote using rclone"
		echo "Tip: Use 'rclone config' to set up remotes if not done yet."
		read -rp "Enter rclone remote (e.g., gdrive:my-backups/): " RCLONE_REMOTE
		if [[ -n "$RCLONE_REMOTE" ]]; then
			rclone copy "$BACKUP_DIR" "$RCLONE_REMOTE" --progress
			echo "[✔] Synced to $RCLONE_REMOTE"
		else
			echo "[!] Invalid rclone remote"
		fi
		break
		;;

	5)
		echo "[*] Export skipped. Backup left in place."
		break
		;;

	*)
		echo "Invalid selection. Please enter 1–5."
		;;
	esac
done

echo
echo "[✔] Backup process finished successfully."
