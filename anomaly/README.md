# README — Arch Anomaly / Forensics Export Script

## Overview

This script collects a broad snapshot of an Arch Linux system for **anomaly analysis / incident response / troubleshooting**, and packages the results into a zip file.

It exports:

- **systemd journal** (all retained logs; multiple formats)
- **kernel ring buffer** (`dmesg`, via sudo)
- **traditional logs** (`/var/log` archive + inventory)
- **authentication/security focused views** (sshd, sudo, audit transport, failed login grep)
- **process and background activity** (ps listings, systemd units, sessions, network sockets)
- **pacman logs and package cache** (`/var/cache/pacman/pkg`)
- **user cache inventory** (`~/.cache` listing; optional full archive)
- An **ASCII README** describing each artifact
- A **command log** of everything executed
- **SHA256 hashes** for tamper detection
- **resume support** if interrupted
- Optional **redacted bundle** for safer sharing

> Important: “All logs” means _all logs retained on your machine_. Journald may not contain older history if persistent logging wasn’t enabled previously.

---

## Requirements

### Must-have (typically present on Arch)

- `bash`
- `sudo`
- `journalctl` (systemd)
- `tar`
- `ps`
- `systemctl`
- `zip` _(script will attempt to install if missing via pacman)_

### Optional (recommended)

- `pv` → nicer progress/throughput display during journal exports
- `jq` → generates `features.json` (reduced/structured journal fields)
- `ss` (iproute2) → socket inventory
- `lsof` → network connection list
- `pstree` → process tree
- `top` → batch snapshot

If an optional tool isn’t installed, the script skips that part and continues.

---

## Quick start

1. Save the script:

```bash
nano anamoly.sh
```

2. Make it executable:

```bash
chmod +x anamoly.sh
```

3. Run it:

```bash
./anamoly.sh
```

Verbose mode:

```bash
./anamoly.sh -v
```

Create both **RAW** and **REDACTED** bundles:

```bash
./anamoly.sh --redact
```

Force regeneration (ignore resume/skips):

```bash
./anamoly.sh --force
```

Include full `~/.cache` contents (default is inventory only):

```bash
./anamoly.sh --include-user-cache-contents
```

---

## Output structure

The script creates a directory and a zip:

- `arch-forensics-RAW-<host>-<timestamp>/`
- `arch-forensics-RAW-<host>-<timestamp>.zip`

If `--redact` is used, it also creates:

- `arch-forensics-REDACTED-<host>-<timestamp>/`
- `arch-forensics-REDACTED-<host>-<timestamp>.zip`

Inside the RAW folder you’ll find:

### Documentation / integrity

- `README_ASCII.txt` — human-readable description of what each file contains
- `COMMANDS_RUN.txt` — every command executed
- `errors_stderr.log` — stderr output and non-fatal errors
- `SHA256SUMS.txt` — SHA256 hash manifest of generated files (tamper detection)
- `.state` — resume-state file (used internally)

### System info

- `system_info.txt` — kernel, cmdline, disks, mounts, network

### Processes / background activity

- `processes_ps_auxww.txt`
- `processes_ps_structured.txt`
- `processes_ps_sudo.txt`
- `process_tree_pstree.txt` _(if pstree exists)_
- `top_snapshot.txt` _(if top exists)_
- `sessions_who.txt`
- `sessions_w.txt`
- `loginctl_sessions.txt` _(if loginctl exists)_
- `loginctl_users.txt` _(if loginctl exists)_
- `systemd_system_units.txt`
- `systemd_failed_units.txt`
- `systemd_user_units.txt`

### Network snapshots

- `network_listening_sockets.txt` _(if ss exists)_
- `network_all_sockets.txt` _(if ss exists)_
- `lsof_network.txt` _(if lsof exists)_

### Journald exports (all retained)

- `system_logs_current_boot.txt`
- `system_logs_all.txt`
- `journal_iso.txt`
- `journal.json`
- `journal_pretty.json`
- `warnings.txt`
- `errors.txt`
- `logs.csv` (CSV-ish)
- `features.json` _(requires jq)_
- `journal_boot_list.txt`
- `journal.json.gz`

### Kernel logs

- `kernel_logs.txt` (sudo `dmesg`)
- `kernel_logs_human.txt` (`dmesg -T`)

### Traditional logs & package manager

- `varlog_archive.tar.gz` — archive of `/var/log`
- `varlog_filelist.txt` — inventory of `/var/log` files
- `pacman.log` _(if present)_

### Pacman package cache

- `pacman_pkg_cache.tar.gz` — archive of `/var/cache/pacman/pkg`
- `pacman_pkg_cache_filelist.txt` — inventory of cache files

### User cache inventory

- `user_cache/user_cache_filelist_maxdepth3.txt`
- `user_cache/user_cache_contents.tar.gz` _(only if enabled)_

### Security-focused exports

- `ssh_logs.txt`
- `sudo_logs.txt`
- `audit_logs.txt`
- `failed_logins.txt`

### Per-service exports

- `service_<name>.txt` for known services that exist on your system

---

## How verbose mode works (`-v`)

Verbose mode prints:

- step counters, labels
- rough journal size context (`journalctl --disk-usage`)
- live export progress:
  - if `pv` is installed → bytes + rate + time
  - otherwise → prints “wrote X bytes…” periodically during export

---

## Resume support (interruption recovery)

The script is **idempotent**: if you run it again, it will:

- check `.state` and output files
- skip steps that already produced non-empty files
- continue from where it left off

If you want to rebuild everything fresh:

```bash
./anamoly.sh --force
```

---

## Hashing / tamper detection

After each file is generated, the script writes its SHA256 hash into:

- `SHA256SUMS.txt` (RAW bundle)
- `SHA256SUMS_REDACTED.txt` (REDACTED bundle)

Verify integrity later:

```bash
cd arch-forensics-RAW-*/
sha256sum -c SHA256SUMS.txt
```

---

## Redaction mode (`--redact`)

When you run:

```bash
./anamoly.sh --redact
```

The script produces a **second bundle** intended for safer sharing.

### What it does (best-effort)

It creates redacted copies of text-ish outputs (`.txt`, `.log`, `.json`, `.csv`) and masks:

- IPv4 addresses → `[REDACTED_IPv4]`
- IPv6 addresses → `[REDACTED_IPv6]`
- MAC addresses → `[REDACTED_MAC]`
- email addresses → `[REDACTED_EMAIL]`
- `/home/<user>/...` → `/home/[REDACTED_USER]/...`
- long token-like strings (32+ chars) → `[REDACTED_TOKEN]`

### What it does NOT do

- It does **not** perfectly detect all secrets/tokens.
- It does **not** redact **archives** (`.tar.gz`, `.zip`) in the redacted bundle (they’re excluded by default).

> You should still review the redacted bundle before sharing.

---

## Privacy & safety notes

This collection can include:

- usernames, hostnames
- IP addresses and connection endpoints
- full process command lines
- file paths
- package history
- some logs may include tokens or credentials depending on apps/services

If you plan to upload/share:

1. Prefer `--redact`
2. Manually scan:
   - `journal.json` (huge; search for `token`, `Authorization`, `Bearer`, `password`)
   - `sudo_logs.txt`
   - service logs

3. Consider excluding:
   - `user_cache_contents.tar.gz`
   - `pacman_pkg_cache.tar.gz` (size + less useful for sharing)

---

## Troubleshooting

### “command not found”

This script forces a standard PATH at the top. If something is still missing, install it:

- `hostname` missing:

  ```bash
  sudo pacman -S inetutils
  ```

- `pv` (optional but recommended for progress):

  ```bash
  sudo pacman -S pv
  ```

- `jq` (for `features.json`):

  ```bash
  sudo pacman -S jq
  ```

- `lsof`:

  ```bash
  sudo pacman -S lsof
  ```

- `pstree`:

  ```bash
  sudo pacman -S psmisc
  ```

### “journalctl doesn’t show old logs”

That’s journald retention. If you want persistence going forward:

```bash
sudo mkdir -p /var/log/journal
sudo systemctl restart systemd-journald
```

---

## Suggested workflow for anomaly analysis

- Start with:
  - `warnings.txt`, `errors.txt`
  - `failed_logins.txt`, `ssh_logs.txt`, `sudo_logs.txt`
  - `network_listening_sockets.txt`
  - `processes_ps_structured.txt`

- For ML / parsing:
  - `journal.json` or `features.json`

- For package changes:
  - `pacman.log`

---

Cheers
