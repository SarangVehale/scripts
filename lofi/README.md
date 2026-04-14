# 🎵 lofi

A beautiful terminal-based lofi music player written in Rust that streams and caches YouTube audio with a minimalist interface.

## ✨ Features

- **🎧 YouTube Integration** - Stream lofi tracks directly from YouTube URLs
- **💾 Smart Caching** - Automatically downloads tracks for offline playback using yt-dlp
- **🖼️ Dual Layouts** - Choose between Classic (spacious, centered) or Compact (dense, corner) layouts
- **▶️ Full Playback Control** - Play, pause, seek, skip, and resume from where you left off
- **🔀 Shuffle & Repeat** - Multiple playback modes to suit your mood
- **🔍 Search** - Quickly find tracks in your playlist
- **📊 Real-time UI** - Live progress bar, buffering status, and playback information
- **🎚️ Volume Control** - Adjust volume on the fly
- **🐱 Aesthetic Interface** - Catppuccin-inspired color scheme with adorable cat emoji

## 📋 Prerequisites

Before running lofi, ensure you have the following installed:

- **Rust** (1.70 or later) - [Install Rust](https://www.rust-lang.org/tools/install)
- **mpv** - Media player for audio playback

  ```bash
  # macOS
  brew install mpv

  # Ubuntu/Debian
  sudo apt install mpv

  # Arch Linux
  sudo pacman -S mpv
  ```

- **yt-dlp** - YouTube downloader

  ```bash
  # macOS
  brew install yt-dlp

  # Linux
  pip install yt-dlp

  # Or download from: https://github.com/yt-dlp/yt-dlp
  ```

## 🚀 Installation

### 🎯 Quick Install (Recommended)

The installation scripts will automatically:

- ✅ Check and install all prerequisites (Rust, mpv, yt-dlp)
- ✅ Build the project
- ✅ Install the `lofi` command globally
- ✅ Set up configuration

#### Linux / macOS

```bash
git clone https://github.com/SarangVehale/scripts/lofi
cd claude
chmod +x install.sh
./install.sh
```

#### Windows

```powershell
git clone https://github.com/SarangVehale/scripts/lofi
cd claude
powershell -ExecutionPolicy Bypass -File install.ps1
```

> **⚠️ Windows Users Disclaimer:**  
> I'm not responsible for you using Microslop. Seriously, use Linux mate! 🐧  
> But anyways, we love you all not matter what you are and make it work anyway... the install script uses winget to get everything set up.  
> Now I atleast hope you have winget (side eye)

### 📦 Manual Installation

If you prefer to install manually or the script doesn't work:

1. Clone the repository:

   ```bash
   git clone https://github.com/SarangVehale/scripts
   cd claude
   ```

2. Build the project:

   ```bash
   cargo build --release
   ```

3. Run lofi:

   ```bash
   cargo run --release
   ```

   Or use the compiled binary:

   ```bash
   ./target/release/lofi
   ```

## ⚙️ Configuration

### Location

After installation, your configuration file will be at:

- **Linux/macOS**: `~/.local/bin/config/tracks.toml` (also symlinked to `~/.config/lofi/tracks.toml`)
- **Windows**: `%USERPROFILE%\.local\bin\config\tracks.toml` (also copied to `%APPDATA%\lofi\tracks.toml`)

For development (running from source), edit `config/tracks.toml` in the project directory.

### Adding Tracks

Edit your `tracks.toml` file to add your favorite lofi tracks:

```toml
[[track]]
title = "Cozy Spring"
url = "https://youtu.be/fsPRybb-xXg?si=sze_Uhai7STt--vN"

[[track]]
title = "Rainy Cat"
url = "https://youtu.be/9kzE8isXlQY?si=qwF7zAZbtamVusip"

[[track]]
title = "Your Favorite Track"
url = "https://youtube.com/watch?v=..."
```

Each track requires:

- `title` - Display name for the track
- `url` - YouTube URL

## 🎮 Keyboard Controls

### Playback Controls

| Key     | Action                    |
| ------- | ------------------------- |
| `Space` | Play/Pause                |
| `n`     | Next track                |
| `p`     | Previous track            |
| `←` `→` | Seek backward/forward 10s |

### Volume & Settings

| Key     | Action             |
| ------- | ------------------ |
| `↑` `↓` | Volume up/down     |
| `+` `-` | Volume up/down     |
| `s`     | Toggle shuffle     |
| `r`     | Cycle repeat modes |

### UI & Navigation

| Key     | Action                                     |
| ------- | ------------------------------------------ |
| `f`     | Open search                                |
| `↑` `↓` | Navigate search results (when search open) |
| `Enter` | Select search result                       |
| `Esc`   | Close search                               |
| `d`     | Toggle debug overlay                       |
| `q`     | Quit                                       |

## 🏗️ Project Structure

```
lofi/
├── Cargo.toml          # Project dependencies and metadata
├── config/
│   └── tracks.toml     # Track playlist configuration
└── src/
    ├── main.rs         # Main application entry and event loop
    ├── app/            # Application state and logic
    │   ├── config.rs   # Configuration loading
    │   ├── state.rs    # App state management
    │   └── track.rs    # Track data structures
    ├── downloader/     # YouTube downloading logic
    │   └── yt_dlp.rs   # yt-dlp integration
    ├── player/         # Media playback
    │   ├── mpv.rs      # mpv player wrapper
    │   └── ipc.rs      # mpv IPC communication
    ├── ui/             # Terminal UI rendering
    │   └── render.rs   # TUI drawing logic
    └── utils/          # Utility functions
```

## 🔧 How It Works

1. **Streaming First** - When you play a track, lofi immediately starts streaming from YouTube
2. **Background Download** - Meanwhile, yt-dlp downloads the audio in the background
3. **Seamless Switch** - Once downloaded, playback switches to the local file
4. **Resume Support** - Your playback position is saved, so you can continue where you left off
5. **Smart IPC** - Communication with mpv happens through Unix sockets for low-latency control

## 🎨 UI Layouts

On first run, choose your preferred layout:

- **Classic** - Centered cat artwork with spacious layout, perfect for larger terminals
- **Compact** - Cat in corner with denser information display, ideal for smaller screens

## 🐛 Debug Mode

Press `d` to toggle debug overlay, which shows:

- Download progress and status
- Buffer levels
- Playback statistics
- Internal state information

## 📝 Notes

- Downloaded tracks are cached locally for faster subsequent playback
- Playback position is automatically saved every 0.5 seconds
- The app requires a terminal with ANSI color support
- Terminal must be at least 80x24 for optimal display

## 🤝 Contributing

Contributions are welcome! Areas for improvement:

- Additional audio sources (SoundCloud, Spotify, etc.)
- Playlist import/export
- Equalizer controls
- Lyrics display
- Cross-platform compatibility improvements

## 📄 License

[Add your license here]

## 🙏 Acknowledgments

- Built with ❤️ using Rust
- Powered by [mpv](https://mpv.io/) and [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- Inspired by the lofi hip hop community

---

_Enjoy your lofi beats! 🎧✨_
