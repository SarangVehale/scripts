#!/bin/bash
set -e

echo "Installing wallpaper-sorter..."

sudo cp usr/local/bin/wallpaper-sorter /usr/local/bin/
sudo chmod +x /usr/local/bin/wallpaper-sorter

sudo cp usr/local/share/man/man1/wallpaper-sorter.1 /usr/local/share/man/man1/
sudo mandb || true

echo "Installation complete."
echo "Run 'wallpaper-sorter --help' to get started."

