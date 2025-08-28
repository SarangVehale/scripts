# wifi-loop

<i>"Because sometimes NetworkManager just... forgets"</i>

This is a dumb little systemd service that slaps your Wifi-card awake whenever it decides to take a nap. Built on Arch + Hyprland with a MediaTek MT792x card that disconnects more often than Windows asks for updates.

It :

- Yeets `nmcli` at your card when it drops.
- Pings 8.8.8.8 like a 2004 CS:GO kid.
- Reloads the kernel module (`mt7921e`) if things go really south.
- Shouts into `/var/log/wifi-loop.log` with a heartbeat every 30s.
- Rotates logs so your `/var/` doesn't turn into `/var/blaot`

Basically: it keeps you online while Arch does Arch things.

### Install

```bash
git clone https://github.com/SarangVehale/scripts.git
cd scripts/wifi-systemd
chmod +x *.sh
sudo ./setup.sh
```

This drops files into :

- `/usr/local/bin/wifi-loop.sh` -> the bash gremlin
- `/etc/systemd/system/wifi-loop.service` -> the babysitter
- `/etc/logrotate.d/wifi-loop` -> log janitor

And enables the service immediately because if you're runnig this, you already lost patience.

### Usage

Check status

```bash
systemctl status wifi-loop.service
```

Tail logs

```bash
journalctl -u wifi-loop.service -f
```

Or just cat the flat file:

```bash
cat /var/log/wifi-loop.log
```

### Uninstall

```bash
cd wifi-loop
sudo ./uninstall.sh
```

Kills the service, wipes the logs, and gives you your system back
(If you reinstall Arch tomorrow, just skip this step)

### Config

Open `wifi-loop.sh`:

- `DEVICE="wlan0"` -> change if your Wi-fi card identifies as something else.
- `PING_TARGET="8.8.8.8` -> could be Cloudflare, your router, or gentoo.org
- `MAX_FAILS=5` -> how many times we tolerate failure before nuking the driver
- `DRIVER="mt7921e` -> kernel module to yeet/reload when all else fails

After edits

```bash
sudo ./setup.sh
```

to reinstall the daemon.

### Troubleshooting

- No `wlan0`? Run `ip link` and rename in the script.
- Still borked? `systemctl restart NetworkManager` because that fixes 80% of things.
- Still still borked? Probably your kernel hates your Wifi-card
- Still still still borked? You know what to do:
  ```bash
  sudo pacman -S linux-zen
  ```

### Pro tip

Add this to your `~/.bashrc` or `~/.zshrc` for instant "WTF is my Wi-fi DOINGGG" diagnostics:

```bash
alias wtf-wifi='systemctl status wifi-loop.service --no-pager; echo; journalctl -u wifi-loop.service -n 20 --no-pager'
```

Now just run:

```bash
wtf-wifi
```

And you'll get a quick dump of :

- current service state
- last 20 heartbeat log lines

Perfect for when NetworkManager gaslights you with "connected" but your packets are in Narnia.

---

## License

MIT. Do whatever. Break your system. Ship it in your dotfiles. I don't care. YOLO

Now go sleep!! go sleep!!
