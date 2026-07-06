# Native NVR (local video recording)

## Why did I change this

The camera's built-in ("stock") recording is tied to the cloud, can only write to
the SD card, and — worse — it writes diagnostic files that **include your Wi-Fi
password in clear text**. That's bad for privacy.

yi-hack-v6 adds its **own recorder**: it saves video locally, with **no cloud and
no Yi app involved**, and never leaks your Wi-Fi password. You decide where the
clips are stored.

## What you get

- **Private** recording — nothing leaves your network.
- Choose where clips are saved: the **SD card**, a **network share**, or **RAM**
  (temporary).
- Works even **without an SD card** (record straight to a network share).
- Light on the camera: video is saved as-is (no re-encoding), so it barely uses the
  processor.
- Automatic clean-up so the storage never fills up, plus a built-in page to browse
  and play your recordings.

## How to set it up

Everything is in the web interface:

1. **Turn recording on and pick where to store it.**
   Go to **Configurations** and set **Recording (NVR)** to:
   - **SD card** — clips are stored on the SD card,
   - **Network share** — clips are stored on your shared folder (great when running
     without an SD card),
   - **RAM (temporary)** — clips are kept in memory only (lost on reboot; useful
     only together with FTP upload),
   - **Disabled** — no recording.

2. **Set how long to keep clips.**
   In the **Events** page, set the retention (how much free space to keep). The
   oldest recordings are removed automatically when space runs low.

3. **Watch your recordings.**
   Also in the **Events** page: browse recordings by date and time, and press
   **Play** to watch them right in the browser (or download them).

## Recording to a network share (CIFS) — with or without extra security

If you store clips on a **network share**, there's a small security choice to make.
The firmware the camera boots from is served **read-only** (so nothing can tamper
with it), but recordings obviously need a share the camera can **write** to.

You have two options. **Neither is mandatory** — pick what fits you:

### Option 1 — one read-write share for everything (simplest)

Use a single share, with read-write access, for both the firmware and the
recordings. Nothing extra to set up: leave the recording fields blank and the
camera writes clips to the same share it booted from.

```
# Network share settings
HOST  = 192.168.1.10
SHARE = yicam          # this share is READ-WRITE
USER  = yicamera
PASS  = ••••••••
# (recording fields left blank -> recordings go to the same share)
```

Downside: because that one share is writable, a misbehaving device could in theory also touch the firmware on it.
Fine for a simple home setup, less ideal if you want tighter security.

### Option 2 — firmware read-only, recordings on a separate read-write share (recommended)

Keep the firmware on a **read-only** share, and put the recordings on a **separate,
read-write** share. Even if security is compromised, it can only write to the
recordings folder — it can't alter the firmware.

You only need to fill in what's *different* for the recordings share — everything
you leave blank is **inherited** from the firmware share. So if the recordings live
on the same server, with the same login, you just name the other share:

```
# Firmware share (read-only)
HOST  = 192.168.1.10
SHARE = firmware
USER  = yicamera
PASS  = ••••••••

# Recordings share (read-write) — only the name differs, the rest is inherited
RECORDING_SHARE = recordings
```

Want the recordings share to use a **different login** too (e.g. a limited account
that can only write recordings)? Just fill those in as well — again, anything left
blank is inherited:

```
# Firmware share (read-only), read-only account
HOST  = 192.168.1.10
SHARE = firmware
USER  = cam-readonly
PASS  = ••••••••

# Recordings share (read-write), its own write-only account
RECORDING_SHARE = recordings
RECORDING_USER  = cam-recorder
RECORDING_PASS  = ••••••••
# RECORDING_HOST left blank -> same server (192.168.1.10)
```

**How the inheritance works, in one line:** every `RECORDING_…` field you leave
empty falls back to the matching firmware-share field. Set only what changes.

> On the server side, make the recordings share writable by an unprivileged account
> so a compromised device can only ever write there — never anywhere else. (My
> reference setup uses a dedicated, no-login user that owns only the recordings
> folder.)

## Tips

- Recording continuously over Wi-Fi to a network share can be demanding if you have
  many cameras — make sure your network is fast enough.
- Prefer streaming to a central system (like Home Assistant or Frigate) if you want
  heavy, always-on recording; the built-in recorder is perfect for lighter, private,
  per-camera recording.
- Recordings are **never** written to the camera's internal memory (that would wear
  it out).
