#!/bin/bash

# === CONFIG ===
SCRIPT_DIR="$HOME/scripts"
SORTER_SCRIPT="$SCRIPT_DIR/sort-wallpapers.sh"
CACHE_DIR="$HOME/.cache"
LOG_FILE="$CACHE_DIR/wallpaper_sorter.log"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SERVICE_NAME="wallpaper-sort"
WALLPAPER_DIR="$HOME/Pictures/wallpapers"
DAY_DIR="$WALLPAPER_DIR/day"
NIGHT_DIR="$WALLPAPER_DIR/night"
THRESHOLD=100
JOBS=8

mkdir -p "$SCRIPT_DIR" "$CACHE_DIR" "$SYSTEMD_USER_DIR"

# === HANDLE UNINSTALL MODE ===
if [[ "$1" == "--uninstall" ]]; then
    echo "[INFO] Uninstalling wallpaper sorting setup..."

    systemctl --user stop "$SERVICE_NAME.path" "$SERVICE_NAME.service"
    systemctl --user disable "$SERVICE_NAME.path" "$SERVICE_NAME.service"
    rm -f "$SYSTEMD_USER_DIR/$SERVICE_NAME.service" "$SYSTEMD_USER_DIR/$SERVICE_NAME.path"
    systemctl --user daemon-reload

    rm -f "$SORTER_SCRIPT"
    rm -f "$LOG_FILE"

    confirm_and_delete_folder() {
        local dir="$1"
        if [ -d "$dir" ]; then
            if [ -z "$(ls -A "$dir")" ]; then
                echo "[OK] Deleting empty folder: $dir"
                rmdir "$dir"
            else
                echo "[WARN] Folder not empty: $dir"
                echo "Contents:"
                ls -1 "$dir"
                read -rp "Do you want to delete this folder and its contents? [y/N] " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    rm -rf "$dir"
                    echo "[OK] Deleted: $dir"
                else
                    echo "[INFO] Skipped deletion of: $dir"
                fi
            fi
        fi
    }

    confirm_and_delete_folder "$DAY_DIR"
    confirm_and_delete_folder "$NIGHT_DIR"

    echo "[OK] Uninstallation complete."
    exit 0
fi

# === DEPENDENCY CHECK ===
declare -A packages=( ["convert"]="imagemagick" ["pv"]="pv" ["xargs"]="findutils" )
for cmd in "${!packages[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "[MISSING] Required: $cmd (provided by: ${packages[$cmd]})"
        read -rp "Do you want to install '${packages[$cmd]}'? [y/N] " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            sudo pacman -S --noconfirm "${packages[$cmd]}" || {
                echo "[ERROR] Failed to install ${packages[$cmd]}"
                exit 1
            }
        else
            echo "[ABORTED] Dependency '${packages[$cmd]}' not installed."
            exit 1
        fi
    fi
done

# === WRITE SORT SCRIPT ===
mkdir -p "$DAY_DIR" "$NIGHT_DIR"

cat <<'EOF' > "$SORTER_SCRIPT"
#!/bin/bash

BASE_DIR="$HOME/Pictures/wallpapers"
DAY_DIR="$BASE_DIR/day"
NIGHT_DIR="$BASE_DIR/night"
LOG_FILE="$HOME/.cache/wallpaper_sorter.log"
THRESHOLD=100
JOBS=8

process_image() {
    local file="$1"
    [[ "$file" == "$DAY_DIR/"* || "$file" == "$NIGHT_DIR/"* ]] && return
    [[ ! -f "$file" ]] && echo "[ERROR] Skipping non-file: $file" >> "$LOG_FILE" && return

    brightness=$(convert "$file" -resize 1x1 -colorspace Gray -format "%[fx:int(255*mean)]" info: 2>/dev/null)
    if [[ -z "$brightness" ]]; then
        echo "[WARN] Could not determine brightness for $file" >> "$LOG_FILE"
        return
    fi

    if (( brightness >= THRESHOLD )); then
        target_dir="$DAY_DIR"
    else
        target_dir="$NIGHT_DIR"
    fi

    filename=$(basename "$file")
    dest="$target_dir/$filename"

    if [[ -e "$dest" ]]; then
        echo "[SKIP] File exists: $dest" >> "$LOG_FILE"
        return
    fi

    mv "$file" "$dest"
    echo "[$(date '+%F %T')] [OK] [$brightness] $file -> $dest" >> "$LOG_FILE"
}

export -f process_image
export DAY_DIR NIGHT_DIR THRESHOLD LOG_FILE

mkdir -p "$DAY_DIR" "$NIGHT_DIR"

mapfile -d '' files < <(find "$BASE_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) ! -path "$DAY_DIR/*" ! -path "$NIGHT_DIR/*" -print0)

total=${#files[@]}
if (( total == 0 )); then
    echo "[$(date '+%F %T')] [INFO] No unsorted images found." >> "$LOG_FILE"
    exit 0
fi

printf "%s\0" "${files[@]}" | pv -0 -s "$total" --name "Sorting Wallpapers" | \
    xargs -0 -n 1 -P "$JOBS" bash -c 'process_image "$0"'

echo "[$(date '+%F %T')] [INFO] Sorting complete: $total file(s)" >> "$LOG_FILE"

# === CLEANUP ===
echo "[$(date '+%F %T')] [INFO] Cleaning up leftover folders..." >> "$LOG_FILE"

find "$BASE_DIR" -mindepth 1 -type d ! -path "$DAY_DIR" ! -path "$NIGHT_DIR" | while read -r dir; do
    [[ "$dir" == "$DAY_DIR" || "$dir" == "$NIGHT_DIR" ]] && continue

    if [ -z "$(ls -A "$dir")" ]; then
        rmdir "$dir"
        echo "[$(date '+%F %T')] [CLEAN] Removed empty folder: $dir" >> "$LOG_FILE"
    else
        echo
        echo "[WARN] Folder not empty: $dir"
        echo "Contents:"
        ls -1 "$dir"
        read -rp "Do you want to delete this folder and its contents? [y/N] " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            rm -rf "$dir"
            echo "[$(date '+%F %T')] [DELETED] $dir" >> "$LOG_FILE"
        else
            echo "[$(date '+%F %T')] [SKIP] Skipped deletion: $dir" >> "$LOG_FILE"
        fi
    fi
done
EOF

chmod +x "$SORTER_SCRIPT"

# === SYSTEMD UNIT FILES ===
cat <<EOF > "$SYSTEMD_USER_DIR/$SERVICE_NAME.service"
[Unit]
Description=Sort wallpapers into day/night folders

[Service]
Type=oneshot
ExecStart=$SORTER_SCRIPT
EOF

cat <<EOF > "$SYSTEMD_USER_DIR/$SERVICE_NAME.path"
[Unit]
Description=Watch wallpaper directory for changes

[Path]
PathModified=$WALLPAPER_DIR
PathChanged=$WALLPAPER_DIR
DirectoryNotEmpty=$WALLPAPER_DIR

[Install]
WantedBy=default.target
EOF

# === ACTIVATE SYSTEMD PATH ===
systemctl --user daemon-reexec
systemctl --user daemon-reload
systemctl --user enable --now "$SERVICE_NAME.path"

# === INITIAL SORT RUN ===
"$SORTER_SCRIPT"

echo
echo "[OK] Wallpaper sorter installed and configured successfully."
echo "[INFO] Watching directory: $WALLPAPER_DIR"
echo "[INFO] Sorted into: $DAY_DIR and $NIGHT_DIR"
echo "[INFO] Log file: $LOG_FILE"
echo
echo "To uninstall, run:"
echo "  ./setup-wallpaper-sorting.sh --uninstall"

