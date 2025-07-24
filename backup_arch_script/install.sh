#!/bin/bash

set -euo pipefail

# =======================================================
# Arch Linux Restore Script v2 (CLI + GUI Interactive)
# Supports: .tar.zst or backup dir, encrypted secrets,
# symlink dotfiles, service enablement, UI chooser.
#
# Author : Sarang Vehale
# =======================================================

# -----------------------
# Requirements On Demand
# -----------------------
require_tool() {
	local tool="$1"
	if ! command -v "$tool" &>/dev/null; then
		echo "[*] Installing missing tool: $tool"
		sudo pacman -S --needed --noconfirm "$tool"
	fi
}

require_tool zstd
require_tool tar

# -----------------------
# UI Selection
# -----------------------
choose_interface() {
	echo
	echo "Choose your interface:"
	echo "1) TUI (fzf)"
	echo "2) GUI (zenity)"
	read -rp "Enter 1 or 2: " ui_choice

	case "$ui_choice" in
	1)
		UI="fzf"
		require_tool fzf
		;;
	2)
		UI="zenity"
		require_tool zenity
		;;
	*)
		echo "[!] Invalid choice. Defaulting to TUI (fzf)."
		UI="fzf"
		require_tool fzf
		;;
	esac
}
choose_interface

# -----------------------
# Choose Backup Source
# -----------------------
select_backup() {
	local prompt="Select backup directory or .tar.zst file"

	if [[ "$UI" == "fzf" ]]; then
		BACKUP_SRC=$(find ~ -maxdepth 2 -type d -name "arch_backup*" -o -name "*.tar.zst" 2>/dev/null | fzf --prompt "$prompt: ")
	else
		BACKUP_SRC=$(zenity --file-selection --title="$prompt" --filename="$HOME/" --multiple=false)
	fi

	if [[ -z "$BACKUP_SRC" ]]; then
		echo "[!] No backup selected."
		exit 1
	fi

	if [[ -f "$BACKUP_SRC" && "$BACKUP_SRC" == *.tar.zst ]]; then
		DEST_DIR="${BACKUP_SRC%.tar.zst}"
		mkdir -p "$DEST_DIR"
		echo "[*] Extracting archive..."
		tar -I zstd -xf "$BACKUP_SRC" -C "$(dirname "$DEST_DIR")"
		BACKUP_DIR="$DEST_DIR"
	elif [[ -d "$BACKUP_SRC" ]]; then
		BACKUP_DIR="$BACKUP_SRC"
	else
		echo "[!] Invalid backup selected."
		exit 1
	fi
}
select_backup

cd "$BACKUP_DIR"

# -----------------------
# Restore Archives
# -----------------------
restore_tarball() {
	local file="$1"
	local target="$2"
	if [[ -f "$file" ]]; then
		echo "[*] Restoring $(basename "$file") to $target..."
		tar -I zstd -xf "$file" -C "$target"
	else
		echo "[!] $file not found."
	fi
}

restore_all_archives() {
	echo "[*] Restoring: dotfiles, browsers, imp_dirs..."
	restore_tarball "dotfiles.tar.zst" "$HOME"
	restore_tarball "browsers.tar.zst" "$HOME"
	restore_tarball "imp_dirs.tar.zst" "$HOME"
}

# -----------------------
# Restore Secrets (GPG)
# -----------------------
restore_secrets() {
	if [[ -f "secrets.tar.zst.gpg" ]]; then
		require_tool gpg
		echo "[*] Encrypted secrets found. Decrypting..."
		gpg --output secrets.tar.zst --decrypt secrets.tar.zst.gpg || {
			echo "[!] Decryption failed."
			return
		}
	fi

	if [[ -f "secrets.tar.zst" ]]; then
		restore_tarball "secrets.tar.zst" "$HOME"
		chmod 700 "$HOME/.ssh" "$HOME/.gnupg" 2>/dev/null || true
		chmod 600 "$HOME/.ssh/"* "$HOME/.gnupg/"* 2>/dev/null || true
	fi
}

# -----------------------
# Package Restore
# -----------------------
restore_packages() {
	cd "$BACKUP_DIR/pkglist"
	if [[ -f "official.txt.zst" ]]; then zstd -d official.txt.zst --force; fi
	if [[ -f "aur.txt.zst" ]]; then zstd -d aur.txt.zst --force; fi

	if [[ -f "official.txt" ]]; then
		sudo pacman -S --needed --noconfirm - <official.txt || echo "[!] Some official packages failed."
	fi

	if [[ -f "aur.txt" ]]; then
		if ! command -v yay &>/dev/null; then
			echo "[*] Installing yay..."
			require_tool git
			git clone https://aur.archlinux.org/yay.git /tmp/yay && cd /tmp/yay
			makepkg -si --noconfirm
			cd - || exit
		fi
		yay -S --needed --noconfirm - <aur.txt || echo "[!] Some AUR packages failed."
	fi
}

# -----------------------
# Symlink Dotfiles (Optional)
# -----------------------
symlink_dotfiles() {
	echo
	echo "Symlink dotfiles using:"
	echo "1) stow"
	echo "2) chezmoi"
	echo "3) Skip"
	read -rp "Choose (1/2/3): " SYMLINK_CHOICE

	case "$SYMLINK_CHOICE" in
	1)
		require_tool stow
		mkdir -p ~/.dotfiles && mv "$HOME"/.*rc "$HOME/.dotfiles/" 2>/dev/null || true
		cd ~/.dotfiles && stow . && cd -
		echo "[✔] Dotfiles symlinked with stow"
		;;
	2)
		require_tool chezmoi
		chezmoi init --source="$HOME"
		chezmoi apply
		echo "[✔] Dotfiles symlinked with chezmoi"
		;;
	*)
		echo "[*] Skipping symlink setup."
		;;
	esac
}

# -----------------------
# Enable System Services
# -----------------------
enable_services() {
	echo
	echo "[*] Enabling system services..."
	SERVICES=(NetworkManager gdm bluetooth pipewire hyprland)

	for svc in "${SERVICES[@]}"; do
		if systemctl list-unit-files | grep -q "$svc.service"; then
			sudo systemctl enable "$svc.service"
			echo " [✔] $svc.service enabled"
		fi
	done
}

# -----------------------
# Verification
# -----------------------
verify_restore() {
	echo
	echo "[*] Verifying key restore targets..."
	check_path() { [[ -e "$1" ]] && echo " [✔] $1 exists" || echo " [✘] $1 missing"; }
	check_path "$HOME/.config/hypr"
	check_path "$HOME/.ssh"
	check_path "$HOME/.gnupg"
	check_path "$HOME/.mozilla"
	check_path "$HOME/Downloads"
}

# -----------------------
# Run All Steps
# -----------------------
restore_all_archives
restore_secrets
restore_packages
symlink_dotfiles
enable_services
verify_restore

echo
echo "[✔] Restore complete. Please reboot for changes to take full effect."
