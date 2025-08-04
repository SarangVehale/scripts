# Wallpaper Sorter CLI Utility

A fast, configurable, and intelligent wallpaper management tool for Linux. This utility organizes your wallpapers into `day` and `night` folders using filename or EXIF metadata, optionally runs in a loop, and supports `cron` or `systemd` automation — all from an interactive or CLI-based interface.

---

## Features

- [x] Sort wallpapers into **day** and **night** folders
- [x] Detect and handle duplicates (skip, rename, or mass-rename)
- [x] Automatically clean up excess folders (with confirmation)
- [x] Command-line and interactive modes
- [x] `--dry-run`, `--verbose`, `--force`, `--only-folder` options
- [x] YAML config support for persistent settings
- [x] Continuous loop support (`--loop`)
- [x] One-command automation setup via `--setup-cron` or `--setup-timer`
- [x] Includes a man page (`man wallpaper-sorter`)

---

## Installation

### Manual Install

```sh
git clone https://github.com/yourusername/wallpaper-sorter.git
cd wallpaper-sorter
./install.sh
```

After installation, the `wallpaper-sorter` command will be globally available.

---

## Usage

### CLI Mode

```sh
wallpaper-sorter [OPTIONS]
```

#### Common Options

| Option            | Description                                           |
| ----------------- | ----------------------------------------------------- |
| `--dry-run`       | Show planned changes without moving/deleting files    |
| `--verbose`       | Enable detailed output                                |
| `--force`         | Automatically overwrite or delete without prompt      |
| `--only-folder`   | Restrict operations to top-level folder contents only |
| `--loop`          | Continuously watch and sort periodically              |
| `--setup-cron`    | Add a cron job (runs every 30 minutes)                |
| `--setup-timer`   | Set up a systemd user timer (runs every 30 minutes)   |
| `--config <file>` | Use custom YAML config file                           |

---

### Interactive Mode

To run interactively:

```sh
wallpaper-sorter
```

You’ll be presented with a dynamic menu to configure actions such as sorting now, setting up timers, enabling looping, and more.

---

## Configuration

Default config file location:

```sh
~/.config/wallpaper-sorter/config.yml
```

Sample config:

```yaml
source_dir: /home/username/Pictures/wallpapers
target_dir: /home/username/Pictures/sorted
classification: daynight
auto_cleanup: true
prompt_on_duplicate: true
log_file: ~/.cache/wallpaper_sorter.log
```

---

## Examples

Dry-run with detailed logs and forced actions:

```sh
wallpaper-sorter --dry-run --verbose --force
```

Add automation (runs every 30 min):

```sh
wallpaper-sorter --setup-timer
# or
wallpaper-sorter --setup-cron
```

---

## Uninstallation

To remove the utility:

```sh
sudo rm /usr/local/bin/wallpaper-sorter
sudo rm /usr/local/share/man/man1/wallpaper-sorter.1
```

---

## Contributing

Contributions and improvements are welcome. Please file issues or submit pull requests via GitHub.

---

## License

This project is licensed under the [MIT License](./LICENSE)

---

## Manual

After installation, view the manual using:

```sh
man wallpaper-sorter
```

---
