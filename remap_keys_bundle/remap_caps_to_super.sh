# Why and what is this script
#   This script basically remaps caps lock to super/ windows key 
#   Why this script you say?? Well because my crusty ass keybaord broke and it's only fuckin key that doesnot work is the super key
#   So I remapped it's ass to caps lock
#   Becauuuseee!! Why the heck not. Who uses caps lock anyways !! 
#   How do I use capitalize then ?? Use the damn shift key mate and stop being a d*ck

# What does this script do 
#   Windows : Prompts to install Powertoys and offers optional Powershell automation script for remap on external keyboard 
#   Linux : Installs `keyd`, detects keyboard, and reamps Caps -> Super only for external device
#   macOS (Why not) : Uses hidutil to remap Caps Lock -> Command, simulating super key.

# To my dear windows friends -> Kindly run this from Git bash, WSL, or just run the powershell manually. Or else I don't give a f*&*k

# | Feature                                            | Support           |
# | -------------------------------------------------- | ----------------- |
# | OS detection (Linux/macOS/Windows)                 | ✅                 |
# | Sudo/admin privilege check                         | ✅                 |
# | Caps Lock → Super remap                            | ✅                 |
# | Per-device remap on Linux (via `keyd`)             | ✅                 |
# | Native remap on macOS (via `hidutil`)              | ✅                 |
# | PowerToys remap on Windows                         | ✅                 |
# | **Failsafe for Windows** if PowerToys doesn't work | ✅ Uses AutoHotKey |
# | Friendly prompts, ASCII emojis                     | ✅                 |
#
#
# How to use it :
#   Linx/ macos :
#     chmod +x remap_caps_to_super.sh
#     ./remap_caps_to_super
#
#   Windows :
#     * Open git bash or wsl 
#     * Run :
#           bash remap_caps_to_super.sh
#
# You'll Get : 
#     ✅ Linux: /etc/keyd/<device>.conf auto-created
#
#     ✅ macOS: hidutil remap applied
#
#     ✅ Windows:
#
#         remap_caps_to_win.ahk (fallback if PowerToys fails)
#
#         watch_keyboard_and_toggle_remap.ps1 (device-aware)
##########################################################################################



#!/bin/bash

# ╭──────────────────────────────────────────╮
# │  Universal Caps Lock → Super Remapper    │
# │  Works on Linux, macOS, and Windows      │
# │  Author: Sarang Vehale For smart folks & dum dums │
# ╰──────────────────────────────────────────╯
 
set -e

# 🎨 Styling
EMOJI_OK="✅"
EMOJI_WARN="⚠️"
EMOJI_ERR="❌"
EMOJI_KEY="🔑"
EMOJI_DO="🔧"
EMOJI_INFO="ℹ️"
EMOJI_START="🚀"

# 🧠 Ask for sudo/admin where needed
require_sudo() {
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "\n$EMOJI_WARN This script needs elevated privileges."
        echo -n "$EMOJI_KEY Please enter your password to continue: "
        sudo -v || { echo "$EMOJI_ERR Failed to gain sudo privileges."; exit 1; }
        echo "$EMOJI_OK Sudo access granted."
    fi
}

# 🐧 Linux: Use keyd for per-device remap
handle_linux() {
    require_sudo

    . /etc/os-release 2>/dev/null || DISTRO="unknown"

    echo "$EMOJI_DO Installing keyd..."
    case "$ID" in
        arch|manjaro) sudo pacman -Sy --noconfirm keyd || paru -S --noconfirm keyd ;;
        ubuntu|debian) sudo apt update && sudo apt install -y keyd ;;
        fedora) sudo dnf install -y keyd ;;
        *) echo "$EMOJI_ERR Unsupported distro: $ID"; exit 1 ;;
    esac

    echo "$EMOJI_DO Detecting external keyboards..."
    keyboards=$(ls /dev/input/by-id/*-event-kbd 2>/dev/null)

    if [[ -z "$keyboards" ]]; then
        echo "$EMOJI_ERR No keyboards found."
        exit 1
    fi

    echo "$EMOJI_INFO Select the external keyboard:"
    select kb in $keyboards; do
        [[ -n "$kb" ]] && device=$(readlink -f "$kb") && break
        echo "$EMOJI_ERR Invalid selection."
    done

    echo "$EMOJI_DO Reading device info..."
    info=$(sudo keyd -d -i "$device" | head -n 20)
    vendor=$(echo "$info" | grep Vendor | awk '{print $2}')
    product=$(echo "$info" | grep Product | awk '{print $2}')
    name=$(echo "$info" | grep Name | cut -d '"' -f2)
    file="/etc/keyd/${name// /_}.conf"

    echo "$EMOJI_DO Writing keyd config for: $name"
    sudo tee "$file" > /dev/null <<EOF
[ids]
name=$name
vendor=$vendor
product=$product

[main]
capslock = leftmeta
EOF

    sudo systemctl enable --now keyd
    sudo systemctl restart keyd

    echo "$EMOJI_OK Caps Lock remapped to Super for: $name"
    echo "$EMOJI_INFO Reboot or replug keyboard if needed."
}

# 🍏 macOS: Use hidutil (not persistent)
handle_macos() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "$EMOJI_WARN Needs admin rights to run hidutil."
        sudo "$0" && exit 0
    fi

    echo "$EMOJI_DO Applying hidutil remap (Caps → ⌘)..."
    cat <<EOF > caps_to_command.json
{
  "UserKeyMapping":[
    {
      "HIDKeyboardModifierMappingSrc": 0x700000039,
      "HIDKeyboardModifierMappingDst": 0x7000000E3
    }
  ]
}
EOF

    hidutil property --set "$(cat caps_to_command.json)"
    echo "$EMOJI_OK Caps Lock remapped to ⌘ Command (Super)"
    echo "$EMOJI_INFO Use Karabiner-Elements for persistent remapping."
}

# 🪟 Windows: PowerToys + AHK fallback
handle_windows() {
    echo "$EMOJI_INFO Windows detected."

    echo "$EMOJI_DO Checking for PowerToys..."
    if [ -d "$LOCALAPPDATA/Microsoft/PowerToys" ]; then
        echo "$EMOJI_OK PowerToys appears to be installed."
        echo "$EMOJI_DO Please open Keyboard Manager and remap:"
        echo "  Caps Lock → Left Windows"
    else
        echo "$EMOJI_WARN PowerToys not found."
        echo "$EMOJI_INFO Download here: https://github.com/microsoft/PowerToys/releases"
    fi

    read -p "$EMOJI_DO Want to generate a fallback AutoHotKey script? (y/N): " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        cat <<'EOF' > remap_caps_to_win.ahk
; 🔁 Remap Caps Lock → Left Windows key (AutoHotKey fallback)
SetCapsLockState, AlwaysOff
CapsLock::LWin
EOF
        echo "$EMOJI_OK AutoHotKey script saved as remap_caps_to_win.ahk"
        echo "$EMOJI_INFO To use it:"
        echo "  1. Install AutoHotKey: https://www.autohotkey.com/"
        echo "  2. Double-click the script to run it."
        echo "  3. To run at startup, place it in your shell:startup folder."
    fi

    read -p "$EMOJI_DO Generate PowerShell helper for per-device remap? (y/N): " psyn
    if [[ "$psyn" =~ ^[Yy]$ ]]; then
        cat <<'EOF' > watch_keyboard_and_toggle_remap.ps1
$keyboardName = "Your External Keyboard Name Here"
function Enable-Remap {
    Stop-Process -Name PowerToys -Force -ErrorAction SilentlyContinue
    Start-Process "$env:ProgramFiles\PowerToys\PowerToys.exe"
}
function Disable-Remap {
    Stop-Process -Name PowerToys -Force -ErrorAction SilentlyContinue
}
Register-WmiEvent -Class Win32_DeviceChangeEvent -Action {
    $devices = Get-PnpDevice -Class Keyboard | Where-Object { $_.Status -eq "OK" }
    $found = $devices | Where-Object { $_.FriendlyName -like "*$using:keyboardName*" }
    if ($found) { Enable-Remap } else { Disable-Remap }
}
Write-Host "🕵️‍♂️ Watching for keyboard: $keyboardName"
while ($true) { Start-Sleep 5 }
EOF
        echo "$EMOJI_OK PowerShell script saved: watch_keyboard_and_toggle_remap.ps1"
        echo "$EMOJI_INFO Edit and replace the keyboard name as needed."
    fi
}

# 🎬 Main
main() {
    echo "$EMOJI_START Starting Universal Key Remapper..."
    OS="$(uname -s)"

    case "$OS" in
        Linux) handle_linux ;;
        Darwin) handle_macos ;;
        MINGW*|MSYS*|CYGWIN*) handle_windows ;;
        *) echo "$EMOJI_ERR Unsupported OS: $OS" && exit 1 ;;
    esac
}

main

