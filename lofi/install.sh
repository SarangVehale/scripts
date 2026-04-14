#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ASCII art
echo -e "${MAGENTA}"
cat <<"EOF"
    ╭────────────────────────────────╮
    │    🎵 lofi installer v1.0      │
    │    Your terminal music player  │
    ╰────────────────────────────────╯
EOF
echo -e "${NC}"

# Detect OS
OS="unknown"
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
	OS="linux"
	echo -e "${GREEN}✓ Detected: Linux${NC}"
elif [[ "$OSTYPE" == "darwin"* ]]; then
	OS="macos"
	echo -e "${GREEN}✓ Detected: macOS${NC}"
else
	echo -e "${RED}✗ Unsupported OS: $OSTYPE${NC}"
	exit 1
fi

# Check if running as root (we don't want that for most operations)
if [[ $EUID -eq 0 ]]; then
	echo -e "${YELLOW}⚠ Warning: Running as root. This script will use sudo when needed.${NC}"
fi

echo ""
echo -e "${CYAN}=== Checking Prerequisites ===${NC}"
echo ""

# Function to check if a command exists
command_exists() {
	command -v "$1" >/dev/null 2>&1
}

# Function to install package based on OS
install_package() {
	local package=$1
	local install_cmd=""

	if [[ "$OS" == "linux" ]]; then
		if command_exists apt-get; then
			install_cmd="sudo apt-get update && sudo apt-get install -y $package"
		elif command_exists dnf; then
			install_cmd="sudo dnf install -y $package"
		elif command_exists pacman; then
			install_cmd="sudo pacman -S --noconfirm $package"
		elif command_exists yum; then
			install_cmd="sudo yum install -y $package"
		else
			echo -e "${RED}✗ Unable to detect package manager${NC}"
			return 1
		fi
	elif [[ "$OS" == "macos" ]]; then
		if ! command_exists brew; then
			echo -e "${YELLOW}⚠ Homebrew not found. Installing Homebrew...${NC}"
			/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
		fi
		install_cmd="brew install $package"
	fi

	echo -e "${BLUE}Installing $package...${NC}"
	eval $install_cmd
}

# Check Rust
echo -n "Checking for Rust... "
if command_exists rustc; then
	RUST_VERSION=$(rustc --version | cut -d' ' -f2)
	echo -e "${GREEN}✓ Found (v$RUST_VERSION)${NC}"
else
	echo -e "${YELLOW}✗ Not found${NC}"
	echo -e "${BLUE}Installing Rust...${NC}"
	curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
	source "$HOME/.cargo/env"
	echo -e "${GREEN}✓ Rust installed${NC}"
fi

# Check mpv
echo -n "Checking for mpv... "
if command_exists mpv; then
	MPV_VERSION=$(mpv --version | head -n1 | cut -d' ' -f2)
	echo -e "${GREEN}✓ Found (v$MPV_VERSION)${NC}"
else
	echo -e "${YELLOW}✗ Not found${NC}"
	install_package "mpv"
	echo -e "${GREEN}✓ mpv installed${NC}"
fi

# Check yt-dlp
echo -n "Checking for yt-dlp... "
if command_exists yt-dlp; then
	YTDLP_VERSION=$(yt-dlp --version)
	echo -e "${GREEN}✓ Found (v$YTDLP_VERSION)${NC}"
else
	echo -e "${YELLOW}✗ Not found${NC}"
	echo -e "${BLUE}Installing yt-dlp...${NC}"

	if [[ "$OS" == "macos" ]]; then
		install_package "yt-dlp"
	else
		# Use pip or direct download for Linux
		if command_exists pip3; then
			pip3 install --user yt-dlp
		elif command_exists pip; then
			pip install --user yt-dlp
		else
			# Direct download method
			sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
			sudo chmod a+rx /usr/local/bin/yt-dlp
		fi
	fi
	echo -e "${GREEN}✓ yt-dlp installed${NC}"
fi

echo ""
echo -e "${CYAN}=== Building lofi ===${NC}"
echo ""

# Build the project
echo -e "${BLUE}Compiling lofi (this may take a few minutes)...${NC}"
cargo build --release

if [ $? -eq 0 ]; then
	echo -e "${GREEN}✓ Build successful!${NC}"
else
	echo -e "${RED}✗ Build failed${NC}"
	exit 1
fi

echo ""
echo -e "${CYAN}=== Installing lofi ===${NC}"
echo ""

# Create installation directory
INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"

# Copy binary
echo -e "${BLUE}Installing binary to $INSTALL_DIR...${NC}"
cp target/release/lofi "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/lofi"

# Create config directory alongside the binary
CONFIG_DIR="$INSTALL_DIR/config"
mkdir -p "$CONFIG_DIR"

# Copy config
echo -e "${BLUE}Installing configuration...${NC}"
if [ ! -f "$CONFIG_DIR/tracks.toml" ]; then
	cp config/tracks.toml "$CONFIG_DIR/"
	echo -e "${YELLOW}⚠ Configuration file created at: $CONFIG_DIR/tracks.toml${NC}"
	echo -e "${YELLOW}  Edit this file to add your favorite tracks!${NC}"
else
	echo -e "${GREEN}✓ Existing configuration found at $CONFIG_DIR/tracks.toml${NC}"
fi

# Also create a symlink in the user config dir for easy access
USER_CONFIG_DIR="$HOME/.config/lofi"
mkdir -p "$USER_CONFIG_DIR"
if [ ! -f "$USER_CONFIG_DIR/tracks.toml" ]; then
	ln -sf "$CONFIG_DIR/tracks.toml" "$USER_CONFIG_DIR/tracks.toml"
	echo -e "${GREEN}✓ Config also available at: $USER_CONFIG_DIR/tracks.toml${NC}"
fi

echo ""
echo -e "${CYAN}=== Setting up PATH ===${NC}"
echo ""

# Detect shell and add to PATH
SHELL_RC=""
if [[ "$SHELL" == *"zsh"* ]]; then
	SHELL_RC="$HOME/.zshrc"
elif [[ "$SHELL" == *"bash"* ]]; then
	SHELL_RC="$HOME/.bashrc"
else
	SHELL_RC="$HOME/.profile"
fi

# Check if PATH already includes .local/bin
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
	echo -e "${BLUE}Adding $INSTALL_DIR to PATH in $SHELL_RC...${NC}"
	echo "" >>"$SHELL_RC"
	echo "# lofi music player" >>"$SHELL_RC"
	echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >>"$SHELL_RC"
	echo -e "${GREEN}✓ PATH updated${NC}"
	echo -e "${YELLOW}⚠ Run 'source $SHELL_RC' or restart your terminal to use 'lofi' command${NC}"
else
	echo -e "${GREEN}✓ PATH already configured${NC}"
fi

# Make binary available immediately for this session
export PATH="$INSTALL_DIR:$PATH"

echo ""
echo -e "${MAGENTA}"
cat <<"EOF"
    ╭────────────────────────────────────────╮
    │  ✨ Installation Complete! ✨          │
    │                                        │
    │  Type 'lofi' to start playing music    │
    │                                        │
    │  Config: ~/.local/bin/config/tracks.toml │
    │  (or ~/.config/lofi/tracks.toml)       │
    │  Binary: ~/.local/bin/lofi             │
    ╰────────────────────────────────────────╯
EOF
echo -e "${NC}"

echo -e "${CYAN}Quick Start:${NC}"
echo -e "  1. Edit your tracks: ${BLUE}nano $CONFIG_DIR/tracks.toml${NC}"
echo -e "     (or: ${BLUE}nano ~/.config/lofi/tracks.toml${NC})"
echo -e "  2. Launch lofi: ${BLUE}lofi${NC}"
echo -e "  3. Press ${BLUE}space${NC} to play/pause, ${BLUE}q${NC} to quit"
echo ""
echo -e "${GREEN}Enjoy your lofi beats! 🎧✨${NC}"
