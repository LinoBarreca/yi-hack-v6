# Updated core tools & more secure Wi-Fi (busybox, wpa_supplicant, SSH)

## Why did I change this

The camera's basic system tools (`busybox`) and its Wi-Fi component
(`wpa_supplicant`) were years old. Old software can contain known security issues
and is missing handy tools. I updated them to modern, maintained versions.

## What you get

- More secure Wi-Fi connection handling.
- A modern **SSH server** (secure remote access), enabled by default — a safer
  alternative to the old plain-text Telnet.
- More built-in tools available for diagnostics and recovery, without needing an
  SD card.

## How to set it up

**Mostly nothing to configure** — the updated tools are used automatically.

For remote access:

- **SSH** is enabled by default. Connect with any SSH client using the user
  `root` and the camera's IP address.
- You can change the SSH password, and turn Telnet on/off, from the web
  interface under the relevant service settings.

> Tip: keep Telnet **off** (it sends everything in clear text) and use SSH instead.
