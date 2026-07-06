# Shared configuration for all your cameras

## Why did I change this

When you have more than one camera, you usually want them to share most settings
(time zone, RTSP options, MQTT server, and so on). Setting each one up by hand is
tedious and easy to get wrong.

yi-hack-v6 lets you keep **common settings in one place** — on your network share —
and have every camera pick them up automatically at boot. You choose which settings
are shared and which stay unique to each camera.

## What you get

- Configure once, apply everywhere.
- Each camera still keeps its **own identity** (hostname, MQTT name) so they never
  clash — those are never overwritten.
- Change a shared setting in one file and every camera follows on next reboot.

## How to set it up

1. On your network share (the same one used to
   [load the firmware](load-firmware-from-network-share.md)), create a `config`
   folder.
2. Put into it **only the settings files you want to share** across cameras. Any
   file you place there becomes "managed centrally"; anything you leave out stays
   local to each camera.
3. Reboot the cameras. At boot, each camera copies the shared files over its own
   local copy.

In the web interface, settings that come from the share are shown as
**read-only** (managed centrally), so it's clear which values are shared and which
you can still edit per-camera.

> **Kept local on purpose:** a camera's identity (hostname, MQTT client name) and
> its live state (which toggles are on/off, PTZ presets) are never shared — sharing
> them would make cameras collide or lose their settings.
