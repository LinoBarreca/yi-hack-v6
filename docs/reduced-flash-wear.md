# Reduced flash wear (longer camera life)

## Why did I change this

Your camera has a small amount of internal memory (flash) that can only be
rewritten a limited number of times before it wears out. Previous yi-hack versions
wrote to it more often than necessary — for example rewriting a settings file even
when nothing had actually changed or even at each camera boot.
Over months and years, that shortens the life of the camera.

## What you get

- The firmware now writes to internal memory **only when a value really changes**.
- Temporary data is kept in RAM instead of being written to flash.
- Your camera stays reliable for much longer, with far less risk of the internal
  memory wearing out.

## How to set it up

**Nothing to configure.** This protection is always on and works automatically.

If you record video, note that recordings are **never** written to internal flash
(that would wear it out very quickly) — they go to the SD card, a network share or
RAM instead. See [Native NVR (local recording)](native-nvr-recording.md).
