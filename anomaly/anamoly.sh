#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Arch anomaly/forensics bundle exporter
#
# Features:
#  - Verbose mode: -v / --verbose
#  - Progress counters + step numbers
#  - Journald export with live size/progress (uses pv if available; otherwise periodic size)
#  - Hashing (SHA256) of every generated file (tamper detection)
#  - Resume support: re-run safely; skips already-generated non-empty outputs
#  - Redaction mode for safe sharing: --redact (creates a separate redacted bundle)
#
# Usage:
#   ./anamoly.sh                 # normal
#   ./anamoly.sh -v              # verbose
#   ./anamoly.sh --redact        # produces both raw + redacted bundles
#   ./anamoly.sh --redact -v     # verbose + redaction
#   ./anamoly.sh --force         # overwrite/recreate everything
#
# Notes:
#  - journald retention is limited by your system config; “all logs” means all retained.
#  - dmesg and many exports use sudo.
###############################################################################

# Harden PATH for minimal/restricted shells
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}

# ------------------------ Defaults / Flags -----------------------------------
VERBOSE=0
FORCE=0
REDACT=0
INCLUDE_USER_CACHE_CONTENTS=0 # 0 inventory only, 1 also archive ~/.cache (can be huge/sensitive)

# ------------------------ Arg parsing ---------------------------------------
for arg in "$@"; do
	case "$arg" in
	-v | --verbose) VERBOSE=1 ;;
	--force) FORCE=1 ;;
	--redact) REDACT=1 ;;
	--include-user-cache-contents) INCLUDE_USER_CACHE_CONTENTS=1 ;;
	-h | --help)
		cat <<'EOF'
Usage:
  ./anamoly.sh [options]

Options:
  -v, --verbose                    Show what is going on (live progress)
  --force                          Overwrite/recreate outputs even if they exist
  --redact                         Create a separate redacted bundle for safe sharing
  --include-user-cache-contents    Archive ~/.cache contents (default: inventory only)
  -h, --help                       Show help
EOF
		exit 0
		;;
	*)
		echo "Unknown option: $arg" >&2
		echo "Run: ./anamoly.sh --help" >&2
		exit 2
		;;
	esac
done

# ------------------------ Helpers -------------------------------------------
ts_now() { date +%H:%M:%S; }

log() {
	if [[ "$VERBOSE" -eq 1 ]]; then
		echo "[+] $(ts_now) | $*"
	fi
}

say() {
	# always show (key progress)
	echo "[*] $*"
}

need_cmd() { command -v "$1" >/dev/null 2>&1; }

# Safe hostname detection even if `hostname` isn't available
get_host() {
	if command -v hostname >/dev/null 2>&1; then
		hostname
	elif [[ -x /usr/bin/hostname ]]; then
		/usr/bin/hostname 2>/dev/null || true
	elif [[ -r /proc/sys/kernel/hostname ]]; then
		cat /proc/sys/kernel/hostname 2>/dev/null || true
	else
		echo "unknown-host"
	fi
}

HOST="$(get_host)"
HOST="${HOST:-unknown-host}"
TS="$(date +%Y%m%d-%H%M%S)"

OUTDIR_RAW="arch-forensics-RAW-${HOST}-${TS}"
OUTDIR_REDACTED="arch-forensics-REDACTED-${HOST}-${TS}"
ZIP_RAW="${OUTDIR_RAW}.zip"
ZIP_REDACTED="${OUTDIR_REDACTED}.zip"

mkdir -p "${OUTDIR_RAW}"
CMDLOG="${OUTDIR_RAW}/COMMANDS_RUN.txt"
ERRLOG="${OUTDIR_RAW}/errors_stderr.log"
README="${OUTDIR_RAW}/README_ASCII.txt"
STATE="${OUTDIR_RAW}/.state"
HASHMANIFEST="${OUTDIR_RAW}/SHA256SUMS.txt"

touch "$CMDLOG" "$ERRLOG" "$STATE"
: >"$HASHMANIFEST"

record_cmd() {
	{
		echo "### $(date --iso-8601=seconds 2>/dev/null || date)"
		echo "\$ $*"
		echo
	} >>"$CMDLOG"
}

# Resume logic
is_done() {
	local key="$1"
	grep -qx "$key" "$STATE" 2>/dev/null
}

mark_done() {
	local key="$1"
	if ! is_done "$key"; then
		echo "$key" >>"$STATE"
	fi
}

file_ok() {
	local path="$1"
	[[ -f "$path" && -s "$path" ]]
}

hash_file() {
	local path="$1"
	[[ -f "$path" ]] || return 0
	if need_cmd sha256sum; then
		# Use relative path in manifest for portability
		(cd "$OUTDIR_RAW" && sha256sum "$(realpath --relative-to="$OUTDIR_RAW" "$path")") >>"$HASHMANIFEST" 2>>"$ERRLOG" || true
	elif need_cmd shasum; then
		(cd "$OUTDIR_RAW" && shasum -a 256 "$(realpath --relative-to="$OUTDIR_RAW" "$path")") >>"$HASHMANIFEST" 2>>"$ERRLOG" || true
	else
		echo "No sha256sum/shasum available; skipping hashes" >>"$ERRLOG"
	fi
}

# Step/progress counters
STEP=0
TOTAL_STEPS=0
step_begin() {
	STEP=$((STEP + 1))
	echo
	say "[$STEP/$TOTAL_STEPS] $1"
	log "START: $1"
}
step_end() {
	log "END"
}

# Capture command output to file (non-sudo)
capture() {
	local key="$1"
	shift
	local outfile="$1"
	shift
	local label="$1"
	shift

	local path="${OUTDIR_RAW}/${outfile}"

	if [[ "$FORCE" -eq 0 ]] && is_done "$key" && file_ok "$path"; then
		say "    - Skipping (resume): $outfile"
		return 0
	fi

	if [[ "$FORCE" -eq 0 ]] && file_ok "$path"; then
		# If file exists but state missing, treat as done
		mark_done "$key"
		say "    - Skipping (already exists): $outfile"
		return 0
	fi

	log "$label -> $outfile"
	record_cmd "$*"

	if [[ "$VERBOSE" -eq 1 ]]; then
		# show command output live while also writing file
		("$@" 2>>"$ERRLOG" | tee "$path" >/dev/null) || true
	else
		("$@" >"$path" 2>>"$ERRLOG") || true
	fi

	if file_ok "$path"; then
		hash_file "$path"
		mark_done "$key"
	fi
}

# Capture command output to file (sudo)
capture_sudo() {
	local key="$1"
	shift
	local outfile="$1"
	shift
	local label="$1"
	shift

	local path="${OUTDIR_RAW}/${outfile}"

	if [[ "$FORCE" -eq 0 ]] && is_done "$key" && file_ok "$path"; then
		say "    - Skipping (resume): $outfile"
		return 0
	fi

	if [[ "$FORCE" -eq 0 ]] && file_ok "$path"; then
		mark_done "$key"
		say "    - Skipping (already exists): $outfile"
		return 0
	fi

	log "$label -> $outfile"
	record_cmd "sudo $*"

	if [[ "$VERBOSE" -eq 1 ]]; then
		(sudo "$@" 2>>"$ERRLOG" | tee "$path" >/dev/null) || true
	else
		(sudo "$@" >"$path" 2>>"$ERRLOG") || true
	fi

	if file_ok "$path"; then
		hash_file "$path"
		mark_done "$key"
	fi
}

# Journald export with progress/size estimation
# - Uses pv if present to show throughput + bytes
# - Otherwise prints output file size every few seconds in verbose mode
journal_export() {
	local key="$1"
	shift
	local outfile="$1"
	shift
	local label="$1"
	shift

	local path="${OUTDIR_RAW}/${outfile}"

	if [[ "$FORCE" -eq 0 ]] && is_done "$key" && file_ok "$path"; then
		say "    - Skipping (resume): $outfile"
		return 0
	fi

	if [[ "$FORCE" -eq 0 ]] && file_ok "$path"; then
		mark_done "$key"
		say "    - Skipping (already exists): $outfile"
		return 0
	fi

	# Rough estimate (upper bound) from journal disk usage (binary), not exact for text export.
	local est="unknown"
	if sudo journalctl --disk-usage >/dev/null 2>&1; then
		est="$(sudo journalctl --disk-usage 2>/dev/null | tr -s ' ' | sed 's/^/approx disk usage: /')"
	fi

	say "    - Exporting: $outfile"
	if [[ "$VERBOSE" -eq 1 ]]; then
		echo "      (${est})"
	fi

	record_cmd "sudo $*"

	# Export with progress
	if need_cmd pv; then
		# pv shows bytes/throughput; tee to file to allow live viewing if desired
		# Using -b for bytes, -r for rate, -t for timer, -a for average rate
		(sudo "$@" 2>>"$ERRLOG" | pv -b -r -t -a >"$path") || true
	else
		# No pv: run in background and print file size periodically (verbose only)
		if [[ "$VERBOSE" -eq 1 ]]; then
			(sudo "$@" >"$path" 2>>"$ERRLOG") &
			local pid=$!
			while kill -0 "$pid" 2>/dev/null; do
				local sz=0
				sz="$(stat -c '%s' "$path" 2>/dev/null || echo 0)"
				echo "      wrote ${sz} bytes..."
				sleep 2
			done
			wait "$pid" 2>>"$ERRLOG" || true
		else
			(sudo "$@" >"$path" 2>>"$ERRLOG") || true
		fi
	fi

	if file_ok "$path"; then
		hash_file "$path"
		mark_done "$key"
	fi
}

append_readme_entry() {
	local rel="$1"
	local desc="$2"
	local path="${OUTDIR_RAW}/${rel}"

	{
		echo "------------------------------------------------------------"
		echo "File: ${rel}"
		echo "What it is: ${desc}"
		if [[ -f "$path" ]]; then
			echo "Size: $(stat -c '%s bytes' "$path" 2>/dev/null || echo unknown)"
			echo "Line count: $(wc -l <"$path" 2>/dev/null || echo N/A)"
			echo "First 3 lines:"
			head -n 3 "$path" 2>/dev/null || true
		else
			echo "Status: not present"
		fi
		echo
	} >>"$README"
}

# Redaction: create a redacted directory with sanitized copies of text-ish files
# and a redacted ZIP. Archives (tar.gz) are NOT copied in redacted bundle by default.
# This is intentionally conservative.
redact_line_filter() {
	# This function is used via bash -lc in sed/awk pipelines; keep portable.
	cat
}

do_redaction_copy() {
	mkdir -p "$OUTDIR_REDACTED"
	local red_readme="${OUTDIR_REDACTED}/README_REDACTED_ASCII.txt"
	local red_hash="${OUTDIR_REDACTED}/SHA256SUMS_REDACTED.txt"
	: >"$red_hash"

	{
		echo "REDACTED BUNDLE (ASCII README)"
		echo "Generated: $(date --iso-8601=seconds 2>/dev/null || date)"
		echo "Host: ${HOST}"
		echo
		echo "Redaction policy (best-effort):"
		echo "- Masks IPv4, IPv6, MAC addresses, email addresses"
		echo "- Masks /home/<user>/ paths"
		echo "- Masks obvious long token-like strings (very approximate)"
		echo
		echo "IMPORTANT:"
		echo "- Redaction is best-effort and may miss sensitive data."
		echo "- Review before sharing."
		echo
	} >"$red_readme"

	# Copy + redact selected files (text-like). Skip archives by default.
	while IFS= read -r -d '' f; do
		local rel
		rel="$(realpath --relative-to="$OUTDIR_RAW" "$f")"

		# Skip internal state files and big/binary-ish archives
		case "$rel" in
		*.tar.gz | *.zip) continue ;;
		.state) continue ;;
		esac

		local dest="${OUTDIR_REDACTED}/${rel}"
		mkdir -p "$(dirname "$dest")"

		# Only redact regular files
		if [[ -f "$f" ]]; then
			# Heuristic: treat json/txt/csv/log as text; otherwise just copy (rare)
			case "$rel" in
			*.txt | *.log | *.json | *.csv | *.conf | *.service | *.yml | *.yaml)
				# Best-effort redaction:
				# - IPv4: 1.2.3.4 -> [REDACTED_IPv4]
				# - IPv6: xxxx:... -> [REDACTED_IPv6]
				# - MAC: aa:bb:cc:dd:ee:ff -> [REDACTED_MAC]
				# - emails: a@b.com -> [REDACTED_EMAIL]
				# - /home/user -> /home/[REDACTED_USER]
				# - long tokens-ish: 32+ of [A-Za-z0-9._-] -> [REDACTED_TOKEN]
				sed -E \
					-e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/[REDACTED_IPv4]/g' \
					-e 's/\b([A-Fa-f0-9]{1,4}:){2,7}[A-Fa-f0-9]{1,4}\b/[REDACTED_IPv6]/g' \
					-e 's/\b([A-Fa-f0-9]{2}:){5}[A-Fa-f0-9]{2}\b/[REDACTED_MAC]/g' \
					-e 's/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/[REDACTED_EMAIL]/g' \
					-e 's#(/home/)[^/]+#\1[REDACTED_USER]#g' \
					-e 's/\b[A-Za-z0-9._-]{32,}\b/[REDACTED_TOKEN]/g' \
					"$f" >"$dest" 2>/dev/null || cp -a "$f" "$dest"
				;;
			*)
				cp -a "$f" "$dest"
				;;
			esac

			# Hash redacted file
			if need_cmd sha256sum; then
				(cd "$OUTDIR_REDACTED" && sha256sum "$(realpath --relative-to="$OUTDIR_REDACTED" "$dest")") >>"$red_hash" 2>/dev/null || true
			elif need_cmd shasum; then
				(cd "$OUTDIR_REDACTED" && shasum -a 256 "$(realpath --relative-to="$OUTDIR_REDACTED" "$dest")") >>"$red_hash" 2>/dev/null || true
			fi
		fi
	done < <(find "$OUTDIR_RAW" -type f -print0)

	{
		echo "------------------------------------------------------------"
		echo "Contents: redacted copies of raw bundle (archives are excluded by default)."
		echo "Hashes: SHA256SUMS_REDACTED.txt"
		echo
	} >>"$red_readme"

	# Zip the redacted directory
	if ! need_cmd zip; then
		say "zip not found; installing zip (sudo pacman)..."
		sudo pacman -Sy --noconfirm zip >/dev/null 2>>"$ERRLOG" || true
	fi
	zip -r "$ZIP_REDACTED" "$OUTDIR_REDACTED" >/dev/null 2>>"$ERRLOG" || true
}

# ------------------------ Plan steps (for counters) --------------------------
# Count only “main” steps, not every per-service export.
BASE_STEPS=0
inc_steps() { TOTAL_STEPS=$((TOTAL_STEPS + 1)); }

# main steps
inc_steps # 1: README header
inc_steps # 2: System info
inc_steps # 3: Processes
inc_steps # 4: Process tree/top/sessions
inc_steps # 5: Network sockets
inc_steps # 6: systemd units
inc_steps # 7: journal current boot
inc_steps # 8: journal all
inc_steps # 9: journal iso
inc_steps # 10: journal json
inc_steps # 11: journal pretty
inc_steps # 12: journal warnings
inc_steps # 13: journal errors
inc_steps # 14: logs.csv
inc_steps # 15: features.json (jq optional)
inc_steps # 16: boot list
inc_steps # 17: dmesg raw
inc_steps # 18: dmesg human
inc_steps # 19: /var/log archive
inc_steps # 20: /var/log inventory
inc_steps # 21: pacman.log
inc_steps # 22: pacman pkg cache archive
inc_steps # 23: pacman pkg cache inventory
inc_steps # 24: user cache inventory
inc_steps # 25: user cache archive (optional but count anyway)
inc_steps # 26: auth/security filtered exports
inc_steps # 27: per-service logs loop
inc_steps # 28: finalize README + hashes
inc_steps # 29: zip raw bundle
if [[ "$REDACT" -eq 1 ]]; then
	inc_steps # 30: redacted bundle
fi

# ------------------------ README header --------------------------------------
step_begin "Initialize README + bundle metadata"
{
	echo "ARCH FORENSICS/ANOMALY EXPORT BUNDLE (ASCII README)"
	echo "Generated: $(date --iso-8601=seconds 2>/dev/null || date)"
	echo "Host: ${HOST}"
	echo
	echo "Options:"
	echo "- verbose: ${VERBOSE}"
	echo "- force: ${FORCE}"
	echo "- redact: ${REDACT}"
	echo "- include user cache contents: ${INCLUDE_USER_CACHE_CONTENTS}"
	echo
	echo "Notes:"
	echo "- No time window was applied; journald exports include all AVAILABLE retained logs."
	echo "- Retention depends on journald config; old logs may not exist if not persisted earlier."
	echo "- Many exports require sudo (journal + dmesg + /var/log + some network/process details)."
	echo "- stderr/non-fatal errors: errors_stderr.log"
	echo
} >"$README"
mark_done "readme_init"
hash_file "$README"
step_end

# ------------------------ System info ----------------------------------------
step_begin "Collect system info"
capture "system_info" "system_info.txt" "System info snapshot" \
	bash -lc '{
    echo "== date =="; date --iso-8601=seconds 2>/dev/null || date
    echo; echo "== uname =="; uname -a || true
    echo; echo "== /proc/cmdline =="; cat /proc/cmdline 2>/dev/null || true
    echo; echo "== uptime =="; uptime 2>/dev/null || true
    echo; echo "== lsblk =="; lsblk 2>/dev/null || true
    echo; echo "== mounts (first 200) =="; mount | head -n 200 2>/dev/null || true
    echo; echo "== ip addr =="; ip addr 2>/dev/null || true
    echo; echo "== ip route =="; ip route 2>/dev/null || true
  }'
append_readme_entry "system_info.txt" "Host context (kernel, disks, mounts, network)."
step_end

# ------------------------ Running processes ----------------------------------
step_begin "Collect running process snapshots"
capture "ps_auxww" "processes_ps_auxww.txt" "ps auxww" ps auxww
append_readme_entry "processes_ps_auxww.txt" "Full process list (ps auxww)."

capture "ps_structured" "processes_ps_structured.txt" "ps structured" \
	bash -lc 'ps -eo pid,ppid,user,stat,lstart,%cpu,%mem,cmd --sort=-%cpu'
append_readme_entry "processes_ps_structured.txt" "Processes with fields, sorted by CPU."

capture_sudo "ps_structured_sudo" "processes_ps_sudo.txt" "ps structured (sudo)" \
	bash -lc 'ps -eo pid,ppid,user,stat,lstart,%cpu,%mem,cmd --sort=-%mem'
append_readme_entry "processes_ps_sudo.txt" "Processes with fields via sudo (may reveal more)."
step_end

# ------------------------ Process tree/top/sessions --------------------------
step_begin "Collect process tree, top snapshot, and session info"
if need_cmd pstree; then
	capture "pstree" "process_tree_pstree.txt" "pstree -a -p" pstree -a -p
	append_readme_entry "process_tree_pstree.txt" "Process tree (pstree -a -p)."
else
	log "pstree not installed; skipping"
fi

if need_cmd top; then
	capture "top_snapshot" "top_snapshot.txt" "top -b -n 1" top -b -n 1 -w 200
	append_readme_entry "top_snapshot.txt" "One-time top snapshot (batch mode)."
else
	log "top not installed; skipping"
fi

capture "who" "sessions_who.txt" "who -a" who -a
append_readme_entry "sessions_who.txt" "Logged-in sessions (who -a)."

capture "w" "sessions_w.txt" "w" w
append_readme_entry "sessions_w.txt" "Logged-in sessions + activity (w)."

if need_cmd loginctl; then
	capture "loginctl_sessions" "loginctl_sessions.txt" "loginctl list-sessions" loginctl list-sessions --no-legend
	append_readme_entry "loginctl_sessions.txt" "systemd-logind sessions list."

	capture "loginctl_users" "loginctl_users.txt" "loginctl list-users" loginctl list-users --no-legend
	append_readme_entry "loginctl_users.txt" "systemd-logind users list."
else
	log "loginctl missing; skipping"
fi
step_end

# ------------------------ Network sockets ------------------------------------
step_begin "Collect network socket snapshots"
if need_cmd ss; then
	capture_sudo "ss_listen" "network_listening_sockets.txt" "ss -tulpn" ss -tulpn
	append_readme_entry "network_listening_sockets.txt" "Listening sockets + owning processes (ss -tulpn)."

	capture_sudo "ss_all" "network_all_sockets.txt" "ss -anp" ss -anp
	append_readme_entry "network_all_sockets.txt" "All sockets + owning processes where available (ss -anp)."
else
	log "ss not installed; skipping"
fi

if need_cmd lsof; then
	capture_sudo "lsof_net" "lsof_network.txt" "lsof -nP -i" lsof -nP -i
	append_readme_entry "lsof_network.txt" "Network connections (lsof -i)."
else
	log "lsof not installed; skipping"
fi
step_end

# ------------------------ systemd units --------------------------------------
step_begin "Collect systemd unit state (system + user)"
capture_sudo "systemd_units_all" "systemd_system_units.txt" "systemctl list-units --all" \
	systemctl list-units --all --no-pager
append_readme_entry "systemd_system_units.txt" "All system systemd units."

capture_sudo "systemd_failed" "systemd_failed_units.txt" "systemctl --failed" \
	systemctl --failed --no-pager
append_readme_entry "systemd_failed_units.txt" "Failed system systemd units."

capture "systemd_user_units" "systemd_user_units.txt" "systemctl --user list-units --all" \
	bash -lc 'systemctl --user list-units --all --no-pager 2>/dev/null || true'
append_readme_entry "systemd_user_units.txt" "All user systemd units (if available in this session)."
step_end

# ------------------------ Journald exports (all retained) ---------------------
step_begin "Export journald: current boot"
journal_export "journal_boot" "system_logs_current_boot.txt" "journalctl -b" \
	journalctl -b --no-pager
append_readme_entry "system_logs_current_boot.txt" "Journal for current boot (-b)."
step_end

step_begin "Export journald: all boots (default)"
journal_export "journal_all" "system_logs_all.txt" "journalctl" \
	journalctl --no-pager
append_readme_entry "system_logs_all.txt" "Journal for all retained logs across boots."
step_end

step_begin "Export journald: ISO timestamps"
journal_export "journal_iso" "journal_iso.txt" "journalctl -o short-iso" \
	journalctl -o short-iso --no-pager
append_readme_entry "journal_iso.txt" "All retained journal logs with ISO timestamps."
step_end

step_begin "Export journald: JSON lines"
journal_export "journal_json" "journal.json" "journalctl -o json" \
	journalctl -o json --no-pager
append_readme_entry "journal.json" "All retained journal logs as JSON objects (one per line)."
step_end

step_begin "Export journald: Pretty JSON"
journal_export "journal_json_pretty" "journal_pretty.json" "journalctl -o json-pretty" \
	journalctl -o json-pretty --no-pager
append_readme_entry "journal_pretty.json" "Pretty-printed JSON (very large)."
step_end

step_begin "Export journald: warnings"
journal_export "journal_warn" "warnings.txt" "journalctl -p warning" \
	journalctl -p warning --no-pager
append_readme_entry "warnings.txt" "Journal entries with priority WARNING and above."
step_end

step_begin "Export journald: errors"
journal_export "journal_err" "errors.txt" "journalctl -p err" \
	journalctl -p err --no-pager
append_readme_entry "errors.txt" "Journal entries with priority ERR and above."
step_end

step_begin "Export journald: CSV-ish (short-iso collapsed spaces)"
journal_export "journal_csv" "logs.csv" "journalctl -o short-iso | sed" \
	bash -lc 'journalctl -o short-iso --no-pager | sed "s/  */,/g"'
append_readme_entry "logs.csv" "CSV-ish export (spaces collapsed to commas)."
step_end

step_begin "Export journald: reduced-field features.json (jq optional)"
if need_cmd jq; then
	journal_export "journal_features" "features.json" "journalctl -o json | jq" \
		bash -lc 'journalctl -o json --no-pager | jq -c "{time:.__REALTIME_TIMESTAMP, unit:._SYSTEMD_UNIT, comm:._COMM, pid:._PID, uid:._UID, gid:._GID, pri:.PRIORITY, msg:.MESSAGE}"'
else
	say "    - jq not installed; skipping features.json"
	echo "jq not installed; features.json not generated." >>"$ERRLOG"
fi
append_readme_entry "features.json" "Reduced-field JSON lines from journal (requires jq)."
step_end

step_begin "Export journald: boot list"
capture_sudo "journal_boot_list" "journal_boot_list.txt" "journalctl --list-boots" \
	journalctl --list-boots --no-pager
append_readme_entry "journal_boot_list.txt" "List of boots known to journald (IDs + time ranges)."
step_end

# Gzip journal.json (handy)
step_begin "Compress journal.json (journal.json.gz)"
if [[ "$FORCE" -eq 1 || ! -s "${OUTDIR_RAW}/journal.json.gz" ]]; then
	record_cmd "gzip -c ${OUTDIR_RAW}/journal.json > ${OUTDIR_RAW}/journal.json.gz"
	gzip -c "${OUTDIR_RAW}/journal.json" >"${OUTDIR_RAW}/journal.json.gz" 2>>"$ERRLOG" || true
	hash_file "${OUTDIR_RAW}/journal.json.gz"
	mark_done "journal_json_gz"
else
	say "    - Skipping (already exists): journal.json.gz"
fi
append_readme_entry "journal.json.gz" "Gzipped journal JSON lines."
step_end

# ------------------------ Kernel logs (sudo) ---------------------------------
step_begin "Export kernel logs: dmesg raw (sudo)"
capture_sudo "dmesg_raw" "kernel_logs.txt" "dmesg" dmesg
append_readme_entry "kernel_logs.txt" "Kernel ring buffer (raw dmesg)."
step_end

step_begin "Export kernel logs: dmesg -T (sudo)"
capture_sudo "dmesg_human" "kernel_logs_human.txt" "dmesg -T" dmesg -T
append_readme_entry "kernel_logs_human.txt" "Kernel ring buffer with human-readable timestamps."
step_end

# ------------------------ /var/log (archive + inventory) ---------------------
step_begin "Archive /var/log (varlog_archive.tar.gz)"
if [[ "$FORCE" -eq 1 || ! -s "${OUTDIR_RAW}/varlog_archive.tar.gz" ]]; then
	record_cmd "sudo tar -czf ${OUTDIR_RAW}/varlog_archive.tar.gz /var/log"
	sudo tar -czf "${OUTDIR_RAW}/varlog_archive.tar.gz" /var/log >/dev/null 2>>"$ERRLOG" || true
	hash_file "${OUTDIR_RAW}/varlog_archive.tar.gz"
	mark_done "varlog_archive"
else
	say "    - Skipping (already exists): varlog_archive.tar.gz"
fi
append_readme_entry "varlog_archive.tar.gz" "Compressed archive of /var/log."
step_end

step_begin "Inventory /var/log files (varlog_filelist.txt)"
capture_sudo "varlog_filelist" "varlog_filelist.txt" "find /var/log file inventory" \
	bash -lc 'find /var/log -type f -printf "%p\t%TY-%Tm-%Td %TH:%TM:%TS\t%s\n" 2>/dev/null | sort'
append_readme_entry "varlog_filelist.txt" "Inventory of /var/log files (mtime + size)."
step_end

# pacman.log (separate file)
step_begin "Copy /var/log/pacman.log (if present)"
if [[ -f /var/log/pacman.log ]]; then
	if [[ "$FORCE" -eq 1 || ! -s "${OUTDIR_RAW}/pacman.log" ]]; then
		record_cmd "sudo cp -a /var/log/pacman.log ${OUTDIR_RAW}/pacman.log"
		sudo cp -a /var/log/pacman.log "${OUTDIR_RAW}/pacman.log" 2>>"$ERRLOG" || true
		hash_file "${OUTDIR_RAW}/pacman.log"
		mark_done "pacman_log"
	else
		say "    - Skipping (already exists): pacman.log"
	fi
else
	say "    - pacman.log not found; skipping"
fi
append_readme_entry "pacman.log" "Pacman transaction log (installs/upgrades/removals)."
step_end

# ------------------------ Pacman package cache -------------------------------
step_begin "Archive pacman package cache (/var/cache/pacman/pkg)"
if [[ -d /var/cache/pacman/pkg ]]; then
	if [[ "$FORCE" -eq 1 || ! -s "${OUTDIR_RAW}/pacman_pkg_cache.tar.gz" ]]; then
		record_cmd "sudo tar -czf ${OUTDIR_RAW}/pacman_pkg_cache.tar.gz /var/cache/pacman/pkg"
		sudo tar -czf "${OUTDIR_RAW}/pacman_pkg_cache.tar.gz" /var/cache/pacman/pkg >/dev/null 2>>"$ERRLOG" || true
		hash_file "${OUTDIR_RAW}/pacman_pkg_cache.tar.gz"
		mark_done "pacman_cache_archive"
	else
		say "    - Skipping (already exists): pacman_pkg_cache.tar.gz"
	fi
else
	say "    - /var/cache/pacman/pkg not found; skipping"
fi
append_readme_entry "pacman_pkg_cache.tar.gz" "Archive of /var/cache/pacman/pkg (downloaded package files)."
step_end

step_begin "Inventory pacman cache files (pacman_pkg_cache_filelist.txt)"
if [[ -d /var/cache/pacman/pkg ]]; then
	capture_sudo "pacman_cache_filelist" "pacman_pkg_cache_filelist.txt" "find pacman pkg cache inventory" \
		bash -lc 'find /var/cache/pacman/pkg -maxdepth 1 -type f -printf "%f\t%TY-%Tm-%Td %TH:%TM:%TS\t%s\n" 2>/dev/null | sort'
else
	say "    - /var/cache/pacman/pkg not found; skipping"
fi
append_readme_entry "pacman_pkg_cache_filelist.txt" "Inventory of package files in /var/cache/pacman/pkg."
step_end

# ------------------------ User cache inventory / archive ---------------------
step_begin "User cache inventory (~/.cache, maxdepth 3)"
mkdir -p "${OUTDIR_RAW}/user_cache"
if [[ -d "${HOME}/.cache" ]]; then
	capture "user_cache_inventory" "user_cache/user_cache_filelist_maxdepth3.txt" "find ~/.cache inventory" \
		bash -lc 'find "$HOME/.cache" -maxdepth 3 -type f -printf "%p\t%TY-%Tm-%Td %TH:%TM:%TS\t%s\n" 2>/dev/null | sort'
else
	say "    - ~/.cache not found; skipping"
fi
append_readme_entry "user_cache/user_cache_filelist_maxdepth3.txt" "Inventory of ~/.cache files (mtime + size), depth 3."
step_end

step_begin "Optional: archive ~/.cache contents (disabled by default)"
if [[ "$INCLUDE_USER_CACHE_CONTENTS" -eq 1 && -d "${HOME}/.cache" ]]; then
	if [[ "$FORCE" -eq 1 || ! -s "${OUTDIR_RAW}/user_cache/user_cache_contents.tar.gz" ]]; then
		record_cmd "tar --exclude='*/keyring*' --exclude='*/keyrings*' --exclude='*/ssh*' --exclude='*/gnupg*' -czf ${OUTDIR_RAW}/user_cache/user_cache_contents.tar.gz -C $HOME .cache"
		tar --exclude='*/keyring*' --exclude='*/keyrings*' --exclude='*/ssh*' --exclude='*/gnupg*' \
			-czf "${OUTDIR_RAW}/user_cache/user_cache_contents.tar.gz" -C "$HOME" .cache \
			>/dev/null 2>>"$ERRLOG" || true
		hash_file "${OUTDIR_RAW}/user_cache/user_cache_contents.tar.gz"
		mark_done "user_cache_archive"
	else
		say "    - Skipping (already exists): user_cache_contents.tar.gz"
	fi
else
	say "    - Not enabled; skipping user cache contents archive"
fi
append_readme_entry "user_cache/user_cache_contents.tar.gz" "Optional archive of ~/.cache contents (may be huge/sensitive)."
step_end

# ------------------------ Auth/security filtered exports ----------------------
step_begin "Auth/security filtered exports"
capture_sudo "ssh_logs" "ssh_logs.txt" "journalctl _SYSTEMD_UNIT=sshd.service" \
	journalctl _SYSTEMD_UNIT=sshd.service --no-pager
append_readme_entry "ssh_logs.txt" "Journal entries for sshd.service (if present)."

capture_sudo "sudo_logs" "sudo_logs.txt" "journalctl _COMM=sudo" \
	journalctl _COMM=sudo --no-pager
append_readme_entry "sudo_logs.txt" "Journal entries emitted by sudo."

capture_sudo "audit_logs" "audit_logs.txt" "journalctl _TRANSPORT=audit" \
	journalctl _TRANSPORT=audit --no-pager
append_readme_entry "audit_logs.txt" "Audit transport entries (only if configured)."

capture_sudo "failed_logins" "failed_logins.txt" "journalctl | grep failed auth" \
	bash -lc 'journalctl --no-pager | grep -E "Failed password|authentication failure|invalid user" || true'
append_readme_entry "failed_logins.txt" "Best-effort grep for failed login strings."
step_end

# ------------------------ Per-service logs -----------------------------------
step_begin "Per-service journal exports (common services)"
SERVICES=(
	"sshd"
	"NetworkManager"
	"systemd-logind"
	"systemd-resolved"
	"systemd-timesyncd"
	"firewalld"
	"ufw"
	"docker"
	"containerd"
	"libvirtd"
	"nginx"
	"httpd"
	"apache2"
	"postgresql"
	"mariadb"
)

for s in "${SERVICES[@]}"; do
	# Only export if the unit file exists
	if systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -qx "${s}.service"; then
		capture_sudo "svc_${s}" "service_${s}.txt" "journalctl -u ${s}.service" \
			journalctl -u "${s}.service" --no-pager
		append_readme_entry "service_${s}.txt" "Journal logs for ${s}.service."
	elif systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -qx "${s}"; then
		capture_sudo "svc_${s}" "service_${s}.txt" "journalctl -u ${s}" \
			journalctl -u "${s}" --no-pager
		append_readme_entry "service_${s}.txt" "Journal logs for ${s} unit."
	fi
done
step_end

# ------------------------ Finalize README + hashes ----------------------------
step_begin "Finalize README + hash manifest"
{
	echo "------------------------------------------------------------"
	echo "Command log: COMMANDS_RUN.txt"
	echo "Errors/stderr: errors_stderr.log"
	echo "Hashes: SHA256SUMS.txt"
	echo
	echo "Privacy note:"
	echo "- Logs, process lists, sockets, and caches can contain usernames, hostnames, IPs, file paths,"
	echo "  and occasionally tokens. Review before sharing externally."
	echo
} >>"$README"
hash_file "$README"
hash_file "$CMDLOG"
hash_file "$ERRLOG"
hash_file "$HASHMANIFEST"
mark_done "finalize"
step_end

# ------------------------ Zip raw bundle -------------------------------------
step_begin "Create RAW zip bundle"
if ! need_cmd zip; then
	say "zip not found; installing zip (sudo pacman)..."
	sudo pacman -Sy --noconfirm zip >/dev/null 2>>"$ERRLOG" || true
fi

if [[ "$FORCE" -eq 1 || ! -s "$ZIP_RAW" ]]; then
	record_cmd "zip -r ${ZIP_RAW} ${OUTDIR_RAW}"
	zip -r "$ZIP_RAW" "$OUTDIR_RAW" >/dev/null 2>>"$ERRLOG" || true
else
	say "    - Skipping (already exists): $ZIP_RAW"
fi
mark_done "zip_raw"
step_end

# ------------------------ Redacted bundle ------------------------------------
if [[ "$REDACT" -eq 1 ]]; then
	step_begin "Create REDACTED bundle (best-effort)"
	do_redaction_copy
	mark_done "zip_redacted"
	step_end
fi

# ------------------------ Done ----------------------------------------------
echo
say "Done."
say "RAW folder:      ${OUTDIR_RAW}"
say "RAW zip:         ${ZIP_RAW}"
say "RAW README:      ${OUTDIR_RAW}/README_ASCII.txt"
say "RAW hashes:      ${OUTDIR_RAW}/SHA256SUMS.txt"
if [[ "$REDACT" -eq 1 ]]; then
	say "REDACTED folder: ${OUTDIR_REDACTED}"
	say "REDACTED zip:    ${ZIP_REDACTED}"
	say "REDACTED hashes: ${OUTDIR_REDACTED}/SHA256SUMS_REDACTED.txt"
fi
echo
say "Tip: Re-run the script to resume if interrupted. Use --force to regenerate everything."
