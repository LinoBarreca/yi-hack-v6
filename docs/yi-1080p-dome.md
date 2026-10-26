# Yi 1080p Dome (h20) and the native pipeline

## Why did I change this

The Yi 1080p Dome boots yi-hack-v6 with the stock Xiaomi media stack like the
other models. The **native pipeline** (Camera → Video pipeline → *Native*)
replaces that stack with v6's own. It uses far less CPU and needs no cloud. On the
dome, though, the stock stack also drove the motors, the night vision and the
sound detection. With the stock stack off, those used to be gone.

On the h20 the native pipeline now does all of that itself, so you can switch the
Xiaomi stack off without losing anything you'd miss.

## What you get (native pipeline)

- **Video**: 1080p at about 20 fps plus AAC audio over RTSP. 20 fps is the most
  the chip can encode at 1080p. Set the RTSP stream to **high only** to reach it:
  the small 640x360 stream is then not encoded, and the memory it frees goes to
  the 1080p stream.
- **Pan/tilt**: the arrows in the web UI and Home Assistant, presets, cruise
  (presets or 360°) and **motion tracking**, which follows motion and returns to
  the Home preset after 30 s of quiet. The camera finds its end stops at boot
  (about 10 s of movement).
- **Day/night**: switches the IR LEDs, the IR-cut filter and black & white
  automatically. At night it checks every few minutes, with the IR briefly off,
  whether it is day again: under its own IR a dark room looks as bright as
  daylight. The IR switch in the UI/Home Assistant keeps the LEDs off.
- **Sound detection**: reacts to sounds above your sensitivity setting (in dB:
  30 hears a whisper, 50 normal speech, 90 only a bang). It ignores steady
  background noise such as a fan.
- **Baby crying detection**: listens for the high-pitched, repeated bursts of
  a cry, which normal talking does not trigger. It is a simple detector, not
  Xiaomi's.
- **Speaker**: two-way audio through the RTSP backchannel, as on the y20.
- **Motion-only recording** with the [Native NVR](native-nvr-recording.md).
- Every setting changed from Home Assistant or the web UI is saved and survives
  a reboot.

## How to set it up

1. Flash yi-hack-v6 as described in the main README (files `rootfs_h20` and
   `home_h20`).
2. In the web UI, go to **Camera → Video pipeline**, choose **Native — online**
   and reboot.
3. Optional: under **Services → Streaming**, set the stream to **high** for the
   full 20 fps.

To go back, choose **Stock** and reboot. If the camera does not come up, put an
empty file named `NO_NATIVE` in the root of the SD card: the camera then boots
the stock stack whatever the setting says.

## Good to know

- **Native — offline** (lens correction) has not been tested on the h20 yet.
- Building the native pipeline for the h20 needs the HiSilicon MPP SDK
  (1.0.3.0 works), placed in `src/hisdk`. It is not part of this repository.
  Without it the build still succeeds, but the image only has the stock stack.
- With the native pipeline the Yi app, the cloud and Xiaomi's AI detection
  (people, faces) are off. The camera's processor is too weak to replace the AI
  detection.

## Not done yet

- **Announcements from Home Assistant**: the speaker plays anything written to
  `/tmp/audio_out_fifo` (8 kHz, 16-bit mono PCM). Missing: a CGI that plays a
  sound file or URL, and a Home Assistant script that sends it TTS or a chime.
- **Sound from the web UI**: upload a sound file and play it on the camera. A
  live microphone in the browser needs HTTPS, which the web UI does not have.
