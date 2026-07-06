# Simplified file layout

## Why did I change this

Older yi-hack versions scattered files in different places depending on whether
the camera was running from the SD card or from internal memory. That made things
hard to follow and easy to break.

yi-hack-v6 gives the firmware **one fixed, predictable place** for everything, no
matter where the files physically live (SD card, network share or internal flash).

## What you get

- The camera always looks in the same folders, so behaviour is consistent.
- Switching from an SD card to a network share (or back) doesn't require changing
  anything in the configuration — the firmware sorts it out automatically at boot.
- Easier troubleshooting and fewer "it works on one camera but not the other"
  surprises.

## How to set it up

**Nothing to configure.** This is an internal improvement that works automatically.
You benefit from it just by running yi-hack-v6.
