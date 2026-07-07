# Recovery mode

## Why did I change this

Most camera firmwares need the SD card plugged in at all times to work. But SD
cards wear out, get corrupted, and are one more thing that can fail. We want the
camera to be able to **start and run on its own**, using only its internal memory,
and to keep a simple web page always available so you can fix things even if the
network or the SD card is having problems.

## What you get

- The camera boots and works **without any SD card inserted**. The SD card is only
  needed for the initial firmware flashing and for recovery.
- A lightweight **recovery web page** is *always* available (even before the full
  firmware loads), so you're never locked out.
- Less wear and fewer failures, because the camera isn't constantly reading and
  writing an SD card.

## How to set it up

1. Flash the firmware once with the SD card (see the main README).
2. If something goes wrong (camera can't fully boot), open the camera's web address in your browser, you'll get the **recovery page** instead.
3. On the recovery page you can:
   - set your **Wi-Fi** name and password (useful if your network share changed wifi),
   - turn on **Privacy** (stops all cloud/app features),
   - point the camera at a **network share** to load the full firmware from the
     network — see [Load the firmware from a network share](load-firmware-from-network-share.md),
   - **reboot** the camera.
4. Once configured, you can **remove the SD card** and the camera keeps running.

> If you don't use a network share, keeping the SD card in gives you the full web
> interface and local recording.