#!/bin/bash
set -e

echo "🔧 Installing system essentials for Hyprland on ROG Flow X13 (AMD + NVIDIA)..."

### 🔄 SYSTEM CORE UTILITIES ###
sudo pacman -Syu --noconfirm
sudo pacman -S --noconfirm \
	base-devel \      # Essential build tools
git \              # Version control
wget curl \        # Downloading tools
unzip zip p7zip \  # Archive utilities
rsync \            # File sync
# dosfstools ntfs-3g \  # FAT/NTFS support
lsof pciutils usbutils \  # System utilities
inetutils \               # Basic network tools
acpi acpid \              # Power events and battery info
neofetch \                # System info
htop \                    # Process/system monitors (htop - terminal, btop - GUI)
btop \
	ripgrep fd \           # Fast search tools
jq \                    # JSON parsing
bat \                   # Better cat
fzf \                   # Fuzzy finder
xdg-user-dirs xdg-utils # User dirs and file handlers

### 🔊 AUDIO (PipeWire-based) ###
sudo pacman -S --noconfirm \
	pipewire \
	pipewire-alsa \
	pipewire-pulse \
	wireplumber \
	pavucontrol

### 🔋 POWER MANAGEMENT (TLP only for AMD) ###
sudo pacman -S --noconfirm tlp
sudo systemctl enable --now tlp.service
sudo systemctl enable --now acpid.service

### 📶 NETWORKING ###
sudo pacman -S --noconfirm \
	networkmanager \
	wireless_tools \
	wpa_supplicant \
	dhclient \
	nm-connection-editor \
	network-manager-applet
sudo systemctl enable --now NetworkManager.service

### 🔌 USB, MTP, PHONE, and CAMERA SUPPORT ###
sudo pacman -S --noconfirm \
	gvfs \
	gvfs-mtp \
	gvfs-gphoto2 \
	gvfs-afc \
	libmtp libgphoto2 mtpfs \
	android-udev

### 🖥️ DISPLAY / WAYLAND TOOLS ###
sudo pacman -S --noconfirm \
	wlr-randr \  # Monitor management
kanshi \      # Dynamic display layouts
xorg-xrandr   # Fallback for X-based tools

### 📋 CLIPBOARD & SCREENSHOT UTILITIES ###
sudo pacman -S --noconfirm
# wl-clipboard \  # Wayland clipboard
# cliphist \       # Clipboard history
# grim \           # Screenshot
# slurp \          # Region selection
swappy # Annotate screenshots

### 📁 FILE MANAGERS ###
# sudo pacman -S --noconfirm \
# 	thunar \
# 	thunar-volman \
# 	tumbler \
# 	ranger \
# 	ueberzugpp \
# 	ffmpegthumbnailer

### ⌨️ INPUT DEVICES & PORTALS ###
sudo pacman -S --noconfirm \
	libinput \
	xorg-xev xorg-setxkbmap \
	xdg-desktop-portal-hyprland \
	xdg-desktop-portal-wlr

### 🧠 SYSTEM INFO TOOLS ###
# sudo pacman -S --noconfirm \
# 	smartmontools \  # SSD/HDD health
# 	lshw \            # Hardware info
# 	inxi              # Full system summary

### 🔐 LOGIN & LOCK SCREEN ###
# sudo pacman -S --noconfirm \
# 	greetd \
# 	greetd-tuigreet \
# 	hyprlock

### 🚀 ROG-SPECIFIC UTILITIES ###
if ! command -v yay &>/dev/null; then
	echo "📦 Installing yay (AUR helper)..."
	cd /tmp
	git clone https://aur.archlinux.org/yay.git
	cd yay
	makepkg -si --noconfirm
fi

yay -S --noconfirm \
	asusctl \            # ASUS fan/battery control
rog-control-center \  # GUI frontend for ASUS/ROG
supergfxctl           # iGPU/dGPU/hybrid switcher

sudo systemctl enable --now asusd.service
sudo systemctl enable --now supergfxd.service

### ⚙️ OPTIONAL: AMD-SPECIFIC POWER TOOLS ###
read -p "👉 Install AMD tuning tools (ryzenadj, auto-cpufreq)? [y/N]: " install_amd
if [[ "$install_amd" =~ ^[Yy]$ ]]; then
	yay -S --noconfirm \
		ryzenadj \  # Control cTDP/boost limits
	auto-cpufreq # Auto CPU governor based on usage

	sudo auto-cpufreq --install
fi

### 📦 OPTIONAL: FLATPAK SUPPORT ###
# read -p "👉 Install Flatpak support? [y/N]: " install_flatpak
# if [[ "$install_flatpak" =~ ^[Yy]$ ]]; then
# 	sudo pacman -S --noconfirm flatpak
# 	flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
# fi

### ✅ DONE ###
echo "✅ All essential packages installed and services configured for AMD/NVIDIA + Hyprland!"
echo "💡 Please reboot to finalize driver/daemon changes."
