# [>>] Universal Caps Lock -> Super Remapper

Remap your **Caps Lock** key to act as the **Super/Windows/Command key**, across:

- [*] Linux (Arch, Ubuntu, Debian, Fedora)
- [*] macOS
- [*] Windows (PowerToys or AutoHotKey fallback)

---

## [#] What's Included

| File                                | Description                                                   |
|-------------------------------------|---------------------------------------------------------------|
| `remap_caps_to_super.sh`            | Main cross-platform script                                    |
| `remap_caps_to_win.ahk`             | AutoHotKey fallback script for Windows                        |
| `watch_keyboard_and_toggle_remap.ps1` | PowerShell script for per-device remap                        |
| `caps_to_command.json`              | macOS temporary remap config using `hidutil`                  |
| `README.md`                         | You're reading it :)                                          |

---

## [*] Usage Instructions

### Linux (Arch, Ubuntu, Fedora, etc.)

1. Open terminal.
2. Run:
   ```bash
   chmod +x remap_caps_to_super.sh
   ./remap_caps_to_super.sh
````

3. Select your external keyboard when prompted.
4. Reboot or replug the keyboard to apply the changes.

---

### macOS

1. Open Terminal.
2. Run:

   ```bash
   sudo ./remap_caps_to_super.sh
   ```
3. It applies a temporary remap using `hidutil`.
4. For persistence, use [Karabiner-Elements](https://karabiner-elements.pqrs.org/).

---

### Windows

#### Option 1: PowerToys

1. Download PowerToys: [https://github.com/microsoft/PowerToys/releases](https://github.com/microsoft/PowerToys/releases)
2. Use Keyboard Manager to remap: `Caps Lock` -> `Left Windows`

#### Option 2: AutoHotKey (Fallback)

1. Install AutoHotKey: [https://www.autohotkey.com/](https://www.autohotkey.com/)
2. Run the `remap_caps_to_win.ahk` script.
3. To run at startup, place it in:

   ```
   %APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup
   ```

#### Option 3: Per-Device Remap with PowerShell

1. Open `watch_keyboard_and_toggle_remap.ps1`
2. Replace this line:

   ```powershell
   $keyboardName = "Your External Keyboard Name Here"
   ```
3. Use part of your external keyboard’s name (e.g. "Keychron").
4. Run it in PowerShell as admin:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\watch_keyboard_and_toggle_remap.ps1
   ```

---

## \[?] FAQ

**Q: Why does it ask for my password?**
A: On Linux/macOS, `sudo` is required to change input devices. On Windows, admin rights may be needed to stop/start PowerToys.

**Q: Will this work after reboot?**
A:

* Linux: Yes (with keyd)
* macOS: No, unless used with Karabiner or launch agent
* Windows: Yes (PowerToys or AHK in startup folder)

**Q: Can I undo it?**
A: Yes. All remaps are non-destructive. Just remove/revert the changes.

---

## \[+] Troubleshooting

| Problem                         | Solution                                         |
| ------------------------------- | ------------------------------------------------ |
| keyd not applying after reboot  | Run `sudo systemctl enable keyd`                 |
| macOS remap resets after reboot | Use Karabiner-Elements or set up a launch agent  |
| PowerToys doesn't work          | Use AutoHotKey (`remap_caps_to_win.ahk`) instead |

---

## \[!] Credits

every OS user who hates Caps Lock.

---

## \[\~] License

MIT License — Free to use, share, and improve.




