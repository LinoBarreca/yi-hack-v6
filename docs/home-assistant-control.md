# Control the camera from Home Assistant (MQTT)

## Why did I change this

Normally you change camera settings — turn the status LED off, switch the night
vision (IR) on, mute the microphone — from the Yi phone app, which goes through the
cloud. We wanted to do all of that **locally**, from your own smart home, with no
cloud involved.

yi-hack-v6 publishes the camera to **Home Assistant** over MQTT. The camera shows up
automatically as a device with switches you can flip, and it reports its status back
so Home Assistant always shows the real state.

## What you get

- Control the camera from Home Assistant (or any MQTT client) — no cloud, no app.
- A full set of controls, including ones the old versions didn't expose:
  camera on/off, status LED, IR (night vision), **microphone mute**, image rotate,
  motion detection, AI person/vehicle/animal detection, face detection, motion
  tracking, sound detection, plus sensitivity and cruise as drop-downs.
- Motion and sound events appear in Home Assistant too, so you can build
  automations (e.g. "turn on a light when the camera sees a person").
- **Listening** to the camera's microphone in Home Assistant works through the
  normal video stream (see the note at the end).

## How to set it up

Everything is in the web interface, under the **MQTT** pages:

1. **Connect the camera to your MQTT broker.**
   On the **MQTT** page, enable MQTT and fill in your broker's address, port and
   (if needed) username/password. Make sure **Remote configuration** is left **on**
   — it's what lets Home Assistant send commands to the camera.

2. **Turn on Home Assistant auto-discovery.**
   On the **MQTT Advertise** page, enable **Home Assistant** discovery and the
   **Camera Settings** entities. The camera will announce itself; it appears
   automatically in Home Assistant as a device with all its switches and controls.

3. **Use it.**
   Open the device in Home Assistant and flip the switches. Changes take effect on
   the camera immediately, and the state shown in Home Assistant follows the real
   camera state.

You can also change these same settings directly from the camera's own web
interface, on the **Camera settings** page (including the new **Microphone**
on/off).

## About audio

- **Hearing the camera (mic → Home Assistant):** already works. Enable audio on the
  video stream (RTSP) and Home Assistant / Frigate / go2rtc will carry the sound.
  The **Microphone** switch controls whether the mic is live.
- **Talking through the camera (your voice → camera speaker):** not available yet.
  This "push-to-talk" feature is planned for a future update.
