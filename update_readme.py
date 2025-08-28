#!/usr/bin/env python3

import os
import re

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
README = os.path.join(BASE_DIR, "README.md")


def get_description(folder):
    desc_file = os.path.join(BASE_DIR, folder, "DESCRIPTION")
    if os.path.isfile(desc_file):
        with open(desc_file, "r", encoding="utf-8") as f:
            return f.readline().strip()
    return "(no description yet)"


# Collect folder description
folders = [
    f
    for f in os.listdir(BASE_DIR)
    if os.path.isdir(os.path.join(BASE_DIR, f))
    and not f.startswith(".")
    and f not in ["__pycache__", ".git"]
]

entries = [f"- **{folder}** -> {get_description(folder)}" for folder in sorted(folders)]

# Read current README
with open(README, "r", encoding="utf-8") as f:
    readme_text = f.read()

# Replace section between markers
pattern = re.compile(
    r"(<!-- FOLDER-LIST-START -->)(.*?)(<!-- FOLDER-LIST-END -->)", re.DOTALL
)
new_section = "\n".join(entries)
updated_text = re.sub(pattern, r"\1\n" + new_section + r"\n\3", readme_text)

# Write back
with open(README, "w", encoding="utf-8") as f:
    f.write(updated_text)

print("README updated with folder list")
