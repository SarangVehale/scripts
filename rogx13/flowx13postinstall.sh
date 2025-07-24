#!/bin/bash
set -euo pipefail

echo "Installing system essentials for Hyprland on ROG Flow X13 (AMD + NVIDIA)..."

### SYSTEM CORE UTILITIES ###
sudo pacman -Syu --noconfirm
sudo pacman -S --noconfirm base-devel \
	git wget curl \
	neovim unzip jq \
	tmux htop btop \
	networkmanager openssh \
	ntfs-3g

### START NETWORKMANAGER ###
sudo systemctl enable --now NetworkManager.service

### GRAPHICS & HYPRLAND ###
sudo pacman -S --noconfirm \
	hyprland \
	xdg-desktop-portal-hyprland \
	xdg-desktop-portal \
	waybar \
	kitty \
	rofi \
	dunst \
	wl-clipboard \
	brightnessctl \
	alsa-utils \
	sof-firmware \
	pipewire wireplumber \
	gvfs gvfs-mtp udiskie \
	thunar tumbler \
	polkit-kde-agent \
	qt5-wayland qt6-wayland \
	grim slurp swappy \
	swww

### AMD + NVIDIA GPU SETUP ###
sudo pacman -S --noconfirm \
	nvidia-dkms \
	nvidia-utils \
	nvidia-settings \
	opencl-nvidia \
	mesa lib32-mesa \
	libva libva-nvidia-driver \
	vulkan-icd-loader lib32-vulkan-icd-loader \
	vulkan-tools \
	egl-wayland \
	xf86-video-amdgpu

### SUPERGFXCTL FOR GPU SWITCHING ###
sudo pacman -S --noconfirm \
	supergfxctl \
	libxnvctrl

sudo systemctl enable --now supergfxd.service

### AUDIO ###
sudo pacman -S --noconfirm \
	pavucontrol \
	easyeffects

### INSTALL AUR HELPER (yay) IF NOT PRESENT ###
if ! command -v yay &>/dev/null; then
	echo "Installing yay..."
	temp_dir=$(mktemp -d)
	git clone https://aur.archlinux.org/yay.git "$temp_dir/yay"
	pushd "$temp_dir/yay"
	makepkg -si --noconfirm
	popd
	rm -rf "$temp_dir"
fi

### ASUSCTL & ACPID ###
sudo pacman -S --noconfirm asusctl acpid
sudo systemctl enable --now asusd.service
sudo systemctl enable --now acpid.service
systemctl --user enable --now asusd-user.service || true

### OPTIONAL STATIC LED MODE & BATTERY CHARGE CAP ###
asusctl aura -M static || true
asusctl -c 60 || true

### INSTALL ROG-SPECIFIC TOOLS (REGULAR AUR ONLY) ###
yay -S --noconfirm rog-control-center asusctl-gex rog-aura-service

### ENABLE ROG FAN/AURA SERVICES ###
sudo systemctl enable --now power-profiles-daemon.service || true
sudo systemctl enable --now rog-aura.service || true

### HYPERLAND AUTOSTART CONFIG ###
mkdir -p ~/.config/hypr
cat <<EOF >~/.config/hypr/autostart.conf
exec = systemctl --user start asusd-user.service
exec = swww-daemon
exec-once = swww img ~/.config/wallpapers/default.jpg
EOF

echo "Setup complete. Reboot and select the Hyprland session from your display manager or tty login."
echo "Useful commands:"
echo "- 'asusctl aura -m' : List LED modes"
echo "- 'supergfxctl -m hybrid|integrated|dedicated' : Switch GPU mode"
