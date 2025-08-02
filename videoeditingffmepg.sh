import subprocess
import os
import sys
import re

# ----- Timestamp validation -----
def is_valid_timestamp(ts):
    return re.match(r"^\d{2}:\d{2}:\d{2}$", ts)

# ----- Get input file -----
def get_input_file():
    if len(sys.argv) > 1:
        path = sys.argv[1]
    else:
        path = input("Enter the path to your video file: ").strip()

    path = os.path.expanduser(path)          # expands ~ to home
    path = os.path.expandvars(path)          # expands $VAR
    path = os.path.abspath(path)             # full path

    if not os.path.isfile(path):
        print(f"❌ File not found: {path}")
        sys.exit(1)

    return path

# ----- Get ranges from user -----
def get_keep_ranges():
    print("\nEnter timestamp ranges to keep (format: HH:MM:SS HH:MM:SS).")
    print("When done, enter an empty line.\n")

    ranges = []
    while True:
        line = input("Range (e.g. 00:00:10 00:00:45): ").strip()
        if not line:
            break
        parts = line.split()
        if len(parts) != 2:
            print("❌ Invalid format. Use: HH:MM:SS HH:MM:SS")
            continue
        start, end = parts
        if not is_valid_timestamp(start) or not is_valid_timestamp(end):
            print("❌ Invalid timestamp format. Use HH:MM:SS")
            continue
        if start >= end:
            print("❌ Start time must be before end time.")
            continue
        ranges.append((start, end))
    return ranges

# ----- Run ffmpeg -----
def run_trim(input_file, keep_ranges, output_file="output_trimmed.mp4"):
    temp_dir = "ffmpeg_temp"
    os.makedirs(temp_dir, exist_ok=True)

    temp_files = []
    for i, (start, end) in enumerate(keep_ranges):
        temp_out = os.path.join(temp_dir, f"part{i}.ts")
        temp_files.append(temp_out)

        print(f"🟡 Trimming: {start} → {end}")
        cmd = [
            "ffmpeg",
            "-ss", start,
            "-to", end,
            "-i", input_file,
            "-c", "copy",
            "-avoid_negative_ts", "make_zero",
            "-f", "mpegts",
            temp_out
        ]
        subprocess.run(cmd, check=True)

    concat_input = "concat:" + "|".join(temp_files)
    print("🟢 Concatenating trimmed parts...")

    cmd_concat = [
        "ffmpeg",
        "-i", concat_input,
        "-c", "copy",
        output_file
    ]
    subprocess.run(cmd_concat, check=True)

    print(f"\n✅ Done! Output saved to: {output_file}")
    print("🧹 Temporary files stored in: ffmpeg_temp")

# ----- Main -----
if __name__ == "__main__":
    input_file = get_input_file()
    keep_ranges = get_keep_ranges()

    if not keep_ranges:
        print("❌ No valid ranges provided. Exiting.")
        sys.exit(1)

    run_trim(input_file, keep_ranges)

