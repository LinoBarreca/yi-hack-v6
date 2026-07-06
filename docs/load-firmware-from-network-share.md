# Load the firmware from a network share

## Why did I change this

If you have several cameras, updating each one by hand (with an SD card) is slow
and error-prone. Instead, yi-hack-v6 can load the bulk of its software from a
**shared folder on your network** (a NAS, a home server, a Raspberry Pi...).

Update that one folder, reboot the cameras, and they all pick up the new version —
no SD cards to swap.

## What you get

- One place to manage the software for **all** your cameras.
- No SD card needed for day-to-day running (see
  [Run without an SD card](run-without-sd-card.md)).
- Faster, safer updates across your whole fleet.

## What you need

- A network share reachable over your local network (SMB/CIFS — the same kind of
  "shared folder" Windows uses).
- The yi-hack-v6 payload files copied into that share.

## How to set it up

1. Create a shared folder on your NAS/server and copy the yi-hack-v6 payload into
   it (the same `yi-hack-v6` folder you would put on the SD card).
2. On the camera, open the web interface (or the **recovery page** if you're
   starting without the full UI).
3. In the **network share (CIFS)** section, fill in:
   - the **host** (the server's name or IP address),
   - the **share** name,
   - the **user** name (if your share requires one).
4. Press **Test** to check the camera can reach the share.
5. Save, then **remove the SD card and reboot**. The camera now loads its firmware
   from the network.

> **Security tip:** put your cameras on their own isolated network/VLAN. The share
> should only be reachable by the cameras.
