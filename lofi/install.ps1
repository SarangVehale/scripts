# lofi installer for Windows
# Requires PowerShell 5.1 or later and winget

$ErrorActionPreference = "Stop"

# ASCII art
Write-Host ""
Write-Host "    ╭────────────────────────────────╮" -ForegroundColor Magenta
Write-Host "    │    🎵 lofi installer v1.0      │" -ForegroundColor Magenta
Write-Host "    │    Your terminal music player  │" -ForegroundColor Magenta
Write-Host "    ╰────────────────────────────────╯" -ForegroundColor Magenta
Write-Host ""

Write-Host "⚠️  WARNING: You're using Windows..." -ForegroundColor Yellow
Write-Host "    We recommend Linux for the best experience!" -ForegroundColor Yellow
Write-Host "    But we'll make it work anyway... 😅" -ForegroundColor Yellow
Write-Host ""

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "⚠️  Warning: Not running as Administrator." -ForegroundColor Yellow
    Write-Host "   Some installations may require elevation." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "=== Checking Prerequisites ===" -ForegroundColor Cyan
Write-Host ""

# Function to check if a command exists
function Test-CommandExists {
    param($command)
    $null = Get-Command $command -ErrorAction SilentlyContinue
    return $?
}

# Check for winget
Write-Host "Checking for winget... " -NoNewline
if (Test-CommandExists winget) {
    Write-Host "✓ Found" -ForegroundColor Green
} else {
    Write-Host "✗ Not found" -ForegroundColor Red
    Write-Host ""
    Write-Host "ERROR: winget is required but not installed." -ForegroundColor Red
    Write-Host "Please install winget from: https://aka.ms/getwinget" -ForegroundColor Yellow
    Write-Host "Or update Windows to the latest version." -ForegroundColor Yellow
    exit 1
}

# Check Rust
Write-Host "Checking for Rust... " -NoNewline
if (Test-CommandExists rustc) {
    $rustVersion = (rustc --version).Split()[1]
    Write-Host "✓ Found (v$rustVersion)" -ForegroundColor Green
} else {
    Write-Host "✗ Not found" -ForegroundColor Yellow
    Write-Host "Installing Rust via winget..." -ForegroundColor Blue
    winget install --id Rustlang.Rustup -e --silent --accept-source-agreements --accept-package-agreements
    
    # Refresh environment variables
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    if (Test-CommandExists rustc) {
        Write-Host "✓ Rust installed successfully" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Rust installed but not in PATH. Please restart your terminal." -ForegroundColor Yellow
        Write-Host "   Then run this script again." -ForegroundColor Yellow
        exit 1
    }
}

# Check mpv
Write-Host "Checking for mpv... " -NoNewline
if (Test-CommandExists mpv) {
    Write-Host "✓ Found" -ForegroundColor Green
} else {
    Write-Host "✗ Not found" -ForegroundColor Yellow
    Write-Host "Installing mpv.net via winget..." -ForegroundColor Blue
    winget install --id mpv.net -e --silent --accept-source-agreements --accept-package-agreements
    
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    Write-Host "✓ mpv installed" -ForegroundColor Green
}

# Check yt-dlp
Write-Host "Checking for yt-dlp... " -NoNewline
if (Test-CommandExists yt-dlp) {
    $ytdlpVersion = yt-dlp --version
    Write-Host "✓ Found (v$ytdlpVersion)" -ForegroundColor Green
} else {
    Write-Host "✗ Not found" -ForegroundColor Yellow
    Write-Host "Installing yt-dlp via winget..." -ForegroundColor Blue
    winget install --id yt-dlp.yt-dlp -e --silent --accept-source-agreements --accept-package-agreements
    
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    Write-Host "✓ yt-dlp installed" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Building lofi ===" -ForegroundColor Cyan
Write-Host ""

# Build the project
Write-Host "Compiling lofi (this may take a few minutes)..." -ForegroundColor Blue
cargo build --release

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Build successful!" -ForegroundColor Green
} else {
    Write-Host "✗ Build failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Installing lofi ===" -ForegroundColor Cyan
Write-Host ""

# Create installation directory
$installDir = "$env:USERPROFILE\.local\bin"
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

# Copy binary
Write-Host "Installing binary to $installDir..." -ForegroundColor Blue
Copy-Item "target\release\lofi.exe" "$installDir\" -Force

# Create config directory alongside the binary
$configDir = "$installDir\config"
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}

# Copy config
Write-Host "Installing configuration..." -ForegroundColor Blue
$configFile = "$configDir\tracks.toml"
if (-not (Test-Path $configFile)) {
    Copy-Item "config\tracks.toml" $configFile -Force
    Write-Host "⚠️  Configuration file created at: $configFile" -ForegroundColor Yellow
    Write-Host "   Edit this file to add your favorite tracks!" -ForegroundColor Yellow
} else {
    Write-Host "✓ Existing configuration found at $configFile" -ForegroundColor Green
}

# Also create a symlink/copy in the user AppData for easy access
$userConfigDir = "$env:APPDATA\lofi"
if (-not (Test-Path $userConfigDir)) {
    New-Item -ItemType Directory -Path $userConfigDir -Force | Out-Null
}
$userConfigFile = "$userConfigDir\tracks.toml"
if (-not (Test-Path $userConfigFile)) {
    Copy-Item $configFile $userConfigFile -Force
    Write-Host "✓ Config also available at: $userConfigFile" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Setting up PATH ===" -ForegroundColor Cyan
Write-Host ""

# Add to user PATH if not already there
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$installDir*") {
    Write-Host "Adding $installDir to PATH..." -ForegroundColor Blue
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$installDir", "User")
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Host "✓ PATH updated" -ForegroundColor Green
    Write-Host "⚠️  You may need to restart your terminal for the 'lofi' command to work" -ForegroundColor Yellow
} else {
    Write-Host "✓ PATH already configured" -ForegroundColor Green
}

# Create a PowerShell alias (optional, for current session)
Set-Alias -Name lofi -Value "$installDir\lofi.exe" -Scope Global

Write-Host ""
Write-Host "    ╭────────────────────────────────────────╮" -ForegroundColor Magenta
Write-Host "    │  ✨ Installation Complete! ✨          │" -ForegroundColor Magenta
Write-Host "    │                                        │" -ForegroundColor Magenta
Write-Host "    │  Type 'lofi' to start playing music    │" -ForegroundColor Magenta
Write-Host "    │                                        │" -ForegroundColor Magenta
Write-Host "    │  Config: %USERPROFILE%\.local\bin\config\tracks.toml" -ForegroundColor Magenta
Write-Host "    │  (or %APPDATA%\lofi\tracks.toml)       │" -ForegroundColor Magenta
Write-Host "    │  Binary: %USERPROFILE%\.local\bin\lofi.exe" -ForegroundColor Magenta
Write-Host "    ╰────────────────────────────────────────╯" -ForegroundColor Magenta
Write-Host ""

Write-Host "Quick Start:" -ForegroundColor Cyan
Write-Host "  1. Edit your tracks: " -NoNewline
Write-Host "notepad $installDir\config\tracks.toml" -ForegroundColor Blue
Write-Host "     (or: " -NoNewline
Write-Host "notepad $userConfigFile" -ForegroundColor Blue -NoNewline
Write-Host ")"
Write-Host "  2. Launch lofi: " -NoNewline
Write-Host "lofi" -ForegroundColor Blue
Write-Host "  3. Press " -NoNewline
Write-Host "space" -ForegroundColor Blue -NoNewline
Write-Host " to play/pause, " -NoNewline
Write-Host "q" -ForegroundColor Blue -NoNewline
Write-Host " to quit"
Write-Host ""
Write-Host "💡 Tip: Consider switching to Linux for a better experience! 🐧" -ForegroundColor Yellow
Write-Host ""
Write-Host "Enjoy your lofi beats! 🎧✨" -ForegroundColor Green
