#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# Logging
###############################################################################

section() {
	echo
	echo "============================================================"
	echo "$1"
	echo "============================================================"
	echo
}

run() {
	echo
	echo "+ $*"
	echo
	"$@"
}

###############################################################################
# Root Check
###############################################################################

if [[ $EUID -ne 0 ]]; then
	echo
	echo "Please run as root:"
	echo
	echo "sudo $0"
	echo
	exit 1
fi

###############################################################################
# Dependency Check
###############################################################################

declare -A REQUIRED=(
	["gum"]="gum"
	["parted"]="parted"
	["mkfs.exfat"]="exfatprogs"
	["mkfs.ntfs"]="ntfs-3g"
	["mkfs.ext4"]="e2fsprogs"
	["mkfs.vfat"]="dosfstools"
	["partprobe"]="util-linux"
	["lsblk"]="util-linux"
)

MISSING_PACKAGES=()
MISSING_COMMANDS=()

for cmd in "${!REQUIRED[@]}"; do
	if ! command -v "$cmd" >/dev/null 2>&1; then
		MISSING_COMMANDS+=("$cmd")
		MISSING_PACKAGES+=("${REQUIRED[$cmd]}")
	fi
done

if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then

	section "Dependency Check"

	echo "Missing commands:"
	echo

	for cmd in "${MISSING_COMMANDS[@]}"; do
		printf "  %-15s -> %s\n" "$cmd" "${REQUIRED[$cmd]}"
	done

	echo
	echo "Packages to install:"
	echo

	mapfile -t UNIQUE_PACKAGES < <(
		printf "%s\n" "${MISSING_PACKAGES[@]}" | sort -u
	)

	printf '  %s\n' "${UNIQUE_PACKAGES[@]}"

	echo
	echo "Command:"
	echo
	echo "  sudo pacman -Sy --needed ${UNIQUE_PACKAGES[*]}"
	echo

	read -rp "Install missing packages? [Y/n] " answer

	if [[ ! "${answer:-Y}" =~ ^([Yy]|)$ ]]; then
		echo "Installation declined."
		exit 1
	fi

	if ! pacman -Sy --needed "${UNIQUE_PACKAGES[@]}"; then
		echo
		echo "Package installation failed or was cancelled."
		exit 1
	fi
fi

###############################################################################
# Verify gum
###############################################################################

if ! command -v gum >/dev/null 2>&1; then
	echo
	echo "gum is not available."
	exit 1
fi

###############################################################################
# USB Detection
###############################################################################

section "Scanning USB Drives"

mapfile -t USB_DRIVES < <(
	lsblk -d -o NAME,SIZE,MODEL,TRAN --noheadings |
		awk '$4=="usb"'
)

if [[ ${#USB_DRIVES[@]} -eq 0 ]]; then
	echo "No USB drives detected."
	exit 1
fi

echo "Detected USB drives:"
echo

printf '  %s\n' "${USB_DRIVES[@]}"

echo

SELECTED=$(
	printf '%s\n' "${USB_DRIVES[@]}" |
		gum choose --header="Select USB Drive"
)

DEVICE_NAME=$(awk '{print $1}' <<<"$SELECTED")
DEVICE="/dev/$DEVICE_NAME"

###############################################################################
# Device Info
###############################################################################

section "Selected Device"

lsblk -f "$DEVICE"

MODEL=$(lsblk -dno MODEL "$DEVICE")
SIZE=$(lsblk -dno SIZE "$DEVICE")

echo
echo "Device : $DEVICE"
echo "Model  : $MODEL"
echo "Size   : $SIZE"
echo

###############################################################################
# Filesystem Selection
###############################################################################

FS_SELECTION=$(
	printf '%s\n' \
		"exfat|Best compatibility (Windows/macOS/Linux)" \
		"ntfs|Windows-focused" \
		"ext4|Linux only" \
		"fat32|Legacy compatibility (4GB file limit)" |
		gum choose --header="Choose Filesystem"
)

FS=$(cut -d'|' -f1 <<<"$FS_SELECTION")

###############################################################################
# Label
###############################################################################

LABEL=$(gum input --placeholder "Volume Label")

if [[ -z "$LABEL" ]]; then
	echo "Volume label cannot be empty."
	exit 1
fi

###############################################################################
# Plan
###############################################################################

section "Planned Operations"

echo "Device      : $DEVICE"
echo "Filesystem  : $FS"
echo "Label       : $LABEL"

echo
echo "Current Layout:"
echo

lsblk -f "$DEVICE"

echo
echo "Commands that will run:"
echo
echo "  parted -s $DEVICE mklabel gpt"
echo "  parted -s $DEVICE mkpart primary 1MiB 100%"

case "$FS" in
exfat)
	echo "  mkfs.exfat -n $LABEL <partition>"
	;;
ntfs)
	echo "  mkfs.ntfs -f -L $LABEL <partition>"
	;;
ext4)
	echo "  mkfs.ext4 -F -L $LABEL <partition>"
	;;
fat32)
	echo "  mkfs.vfat -F 32 -n $LABEL <partition>"
	;;
esac

echo

gum confirm "ALL DATA ON $DEVICE WILL BE DESTROYED. Continue?" || exit 0

###############################################################################
# Unmount
###############################################################################

section "Unmounting Partitions"

while read -r partition; do
	[[ "$partition" == "$DEVICE" ]] && continue

	echo "Unmounting $partition"

	umount "$partition" 2>/dev/null || true

done < <(lsblk -lnpo NAME "$DEVICE")

###############################################################################
# GPT
###############################################################################

section "Creating GPT"

run parted -s "$DEVICE" mklabel gpt

###############################################################################
# Partition
###############################################################################

section "Creating Partition"

run parted -s "$DEVICE" mkpart primary 1MiB 100%

run partprobe "$DEVICE"

if command -v udevadm >/dev/null 2>&1; then
	run udevadm settle
fi

sleep 2

PARTITION=$(lsblk -lnpo NAME "$DEVICE" | tail -n1)

if [[ "$PARTITION" == "$DEVICE" ]]; then
	echo "Failed to detect partition."
	exit 1
fi

echo
echo "Partition detected:"
echo "  $PARTITION"

###############################################################################
# Format
###############################################################################

section "Formatting"

case "$FS" in

exfat)
	run mkfs.exfat -n "$LABEL" "$PARTITION"
	;;

ntfs)
	run mkfs.ntfs -f -L "$LABEL" "$PARTITION"
	;;

ext4)
	run mkfs.ext4 -F -L "$LABEL" "$PARTITION"
	;;

fat32)
	run mkfs.vfat -F 32 -n "$LABEL" "$PARTITION"
	;;

*)
	echo "Unsupported filesystem."
	exit 1
	;;
esac

###############################################################################
# Verify
###############################################################################

section "Verification"

lsblk -f "$DEVICE"

echo
echo "Filesystem : $FS"
echo "Label      : $LABEL"
echo "Partition  : $PARTITION"

###############################################################################
# Mount
###############################################################################

if gum confirm "Mount the drive now?"; then

	MOUNTPOINT="/mnt/$LABEL"

	section "Mounting"

	run mkdir -p "$MOUNTPOINT"
	run mount "$PARTITION" "$MOUNTPOINT"

	echo
	echo "Mounted at:"
	echo "  $MOUNTPOINT"
fi

###############################################################################
# Done
###############################################################################

section "Completed"

echo "Drive successfully formatted."
echo
echo "Device     : $DEVICE"
echo "Partition  : $PARTITION"
echo "Filesystem : $FS"
echo "Label      : $LABEL"
echo
