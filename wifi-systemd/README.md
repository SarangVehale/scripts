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
git clone https://github.com/SarangVehale/scripts
```
