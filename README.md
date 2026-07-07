<p align="center">
    <img height="200" src="https://raw.githubusercontent.com/LinoBarreca/yi-hack-v6/master/imgs/yi-hack-v6-header.png">
</p>
<p align="center">
    <a target="_blank" href="https://github.com/LinoBarreca/yi-hack-v6/releases">
        <img src="https://img.shields.io/github/downloads/LinoBarreca/yi-hack-v6/total.svg" alt="Releases Downloads">
    </a>
</p>

## Why this `yi-hack-v6` firmware?

The answer is simple: I wanted to save 5 euro of SD card on AliExpress, so I decided to write code for a month..
Just kidding..I have 6 Yi cameras..I wanted an easy way to update them all and configure them all together.

## Table of Contents

- [Features](#features)
- [Supported cameras and Firmware Files](#supported-cameras-and-firmware-files)
- [Getting started](#getting-started)
- [Unbrick your camera](#unbrick-your-camera)
- [Acknowledgments](#acknowledgments)
- [Disclaimer](#disclaimer)
- [Donations](#donations)

## Features
This firmware will add the following features:

- **NEW FEATURES**
  - [New, simplified file layout](docs/simplified-file-layout.md)
  - [Minimized flash wear](docs/reduced-flash-wear.md) (reduced unnecessary writes introduced by all the previous yi-hack)
  - [Updated busybox & wpa_supplicant](docs/updated-busybox-wpa.md) (more secure)
  - [Ability to load the firmware from a network share](docs/load-firmware-from-network-share.md) (configurable through the recovery http)
  - [Recovery mode](docs/recovery-mode.md) (recovery http when SD is corrupt or network share has issues)
  - [Ability to share configurations](docs/shared-configuration.md) (user chooses which ones) from the network share to have the same configurations applied to all the cameras.
  - [Native NVR](docs/native-nvr-recording.md) (just make sure your network is fast enough, if you have lots of cameras)
  - [Control the camera from Home Assistant / MQTT](docs/home-assistant-control.md) (LED, IR, microphone and more — no cloud)

- **v5 FEATURES**
  - **RTSP server** - which will allow an RTSP stream of the video while keeping the cloud features enabled (available to all and it is free).
  - **MQTT** - detect motion directly from your home server!
  - WebServer - user-friendly stats and configurations.
  - SSH server -  _Enabled by default._
  - Telnet server -  _Disabled by default. Enabled in recovery mode._
  - FTP server -  _Disabled by default._
  - Web server -  _Enabled by default._
  - The possibility to change some camera settings (copied from the official app):
    - camera on/off
    - video saving mode
    - detection sensitivity
    - status led
    - ir led
    - rotate
  - PTZ support through a web page.
  - Snapshot feature
  - Proxychains-ng - _Disabled by default. Useful if the camera is region-locked._
  - The possibility to disable all the cloud features while keeping the RTSP stream.

## Supported cameras and firmware files

Currently, this project supports the following cameras:
| Camera | rootfs partition | home partition | Base Firmware | Remarks |
| --- | --- | --- | --- | ---- |
| **Yi Home** | rootfs_y18 | home_y18 | 1.8.7.0F_201809191400 | Coming later (no hardware) |
| **Yi 1080p Home** | rootfs_y20 | home_y20 | 2.1.0.0E_201809191630 | Already supported (no releases yet, I'm developing on it) |
| **Yi Dome** | rootfs_v201 | home_v201 | 1.9.1.0J_201809191135 | Coming later (no hardware) |
| **Yi 1080p Dome** | rootfs_h20 | home_h20 | 1.9.2.0I_201812141405 | Coming next |
| **Yi 1080p Cloud Dome** | rootfs_y19 | home_y19 | 1.9.3.0E_201812141519 | Coming next |
| **Yi Outdoor** | rootfs_h30 | home_h30 | 3.0.0.0D_201809111054 | Coming later (no hardware) |

A higher base firmware number than listed above means this project does not support your camera yet.
Get in contact with me and I'll see what I can do.

## Getting Started
1. Check that you have a correct Xiaomi Yi camera. (see the section above)

2. Get a microSD card, preferably of capacity 16 GB or less and format it by selecting File System as FAT32.

**_IMPORTANT: The microSD card must be formatted in FAT32. exFAT formatted microSD cards will not work._**
**I have not formatted any of my 32GB cards to load the firmware. Just copy files directly and it should work.**

<details><summary> (Click) How to format microSD cards > 32GB as FAT32 in Windows 10</summary><p>

For microSD cards larger than 32 GB, Windows 10 only gives you the option to format as NTFS or exFAT. You can create a small partition (e.g. 4 GB) on a large microSD card (e.g. 64 GB) to get the FAT32 formatting option.

* insert microSD card into PC card reader
* open Disk Management (e.g. <kbd>Win</kbd>+<kbd>x</kbd>, <kbd>k</kbd>)
  * Disk Management: delete all partitions on the microSD card
    * right click each partition > "Delete Volume..."
    * repeat until there are no partitions on the card
  * Disk Management: create a new FAT32 partition
    * Right-click on "Unallocated" > "New Simple Volume..."
    * Welcome to the New Simple Volume Wizard: click "Next"
    * Specify Volume Size: 4096 > "Next"
    * Assign Drive Letter or Path: (Any) > "Next"
    * Format Partition: Format this volume with the following settings:
      * File system: FAT32
      * Allocation unit size: Default
      * Volume label: Something
      * Perform a quick format: &#9745;

You should now have a FAT32 partition on your microSD card that will allow the camera to load the firmware files to update to `yi-hack-v6`.

### Example: 4 GB FAT32 partition on 64 GB microSD card

![example: 4 GB FAT32 on 64 GB](imgs/4gb-fat32-on-64gb-card.png)

Alternative way:
* open cmd with admin permissions
* run diskpart
* type "list disk"
* find your SD card (for example Disk 7)
* type "select disk 7"
* if it has one partition - type "select partition 1". If more - delete all the partitions and then create one
* type "format FS=FAT32 QUICK"
* done. 32GB partition in FAT32.

</p></details>

3. Get the correct firmware files for your camera from the latest baseline release link: https://github.com/LinoBarreca/yi-hack-v6/releases/tag/6.0.1

4. Save both files `rootfs_xx` and `home_xx`, and the `yi-hack-v6` folder on the root path of the microSD card.

**_IMPORTANT: Make sure that the filenames stored on the microSD card are correct and didn't get changed. e.g. The firmware filenames for the Yi 1080p Dome camera must be home_h20 and rootfs_h20._**

5. Remove power to the camera, insert the microSD card, and turn the power back ON.

6. The yellow light will come ON and flash for roughly 30 seconds, which means the firmware is being flashed successfully. The camera will boot up.

7. The yellow light will come ON again for the final stage of flashing. This will take up to 2 minutes.

8. Blue light should come ON indicating that your WiFi connection has been successful.

9. Go into the browser and access the web interface of the camera as a website.

**_IMPORTANT: The default hostname is the one with the QR-CODE on the device._**
Scan the qrcode with your phone (not the app), you will obtain a text which *starts* with the letters under the QR.

Access the web interface by entering that text `http://<full text in the qr>` in a web browser. e.g. `http://48USYJ5205FD6E6F`

Since 06-Jul-2026 you can also create a DHCP reservation to provide the hostname.

Depending upon your network setup, accessing the web interface with the hostname **may not work**.
In this case, the IP address of the camera has to be found.
This can be done from the App. Please open the app, and go to the Camera Settings --> Network Info --> IP Address.
Access the web interface by entering the IP address of the camera in a web browser. e.g. `http://192.168.1.5`

10. Done! You are now successfully running yi-hack-v6!

## Unbrick your camera
It should not happen, if the instructions are followed correctly.
Usually a proper reflash will solve.
If you were tinkering and destroyed a partition different from rootfs or homefs by launching a wrong command, extracting the partition from a different camera usually works (unless it's the vd1 which is unique per camera)..
So please avoid playing with partitions if you do not have a backup.

## Troubleshooting

### Wi-Fi is connected, and the camera responds to ping but I'm not able to connect to the web interface
Verify that you did not forget to upload the `yi-hack-v6` folder to the SD card when uploading firmware. If you did, upload it and restart the camera.

### Cannot complete the pairing/wifi settings lost after reboot
Ensure you are using the correct app (Yi Home) to set up the wifi connection. For example, the "Xiaomi Home" app will also generate the correct QR code that will work with your camera for the initial connection, but then after power is removed
the settings will be lost.

## Introducing pre-releases
No pre-releases yet. If you have a camera that I do not own and want to help, please get in contact with me.

## Acknowledgments
Special thanks to the following people and projects, without them `yi-hack-v6` wouldn't be possible.
- @alienatedsec [https://github.com/alienatedsec/yi-hack-v5](https://github.com/alienatedsec/yi-hack-v5)
- @TheCrypt0 - [https://github.com/TheCrypt0/yi-hack-v4](https://github.com/TheCrypt0/yi-hack-v4)
- @shadow-1 - [https://github.com/shadow-1/yi-hack-v3](https://github.com/shadow-1/yi-hack-v3)
- @fritz-smh - [https://github.com/fritz-smh/yi-hack](https://github.com/fritz-smh/yi-hack)
- @niclet  - [https://github.com/niclet/yi-hack-v2](https://github.com/niclet/yi-hack-v2)
- @xmflsct -  [https://github.com/xmflsct/yi-hack-1080p](https://github.com/xmflsct/yi-hack-1080p)
- @dvv - [Ideas for the RSTP stream](https://github.com/shadow-1/yi-hack-v3/issues/126)
- @andy2301 - [Ideas for the RSTP rtsp and rtsp2301](https://github.com/xmflsct/yi-hack-1080p/issues/5#issuecomment-294326131)
- @roleoroleo - [PTZ Implementation](https://github.com/roleoroleo/yi-hack-MStar)
- @roleoroleo - [https://github.com/roleoroleo](https://github.com/roleoroleo)

---
### DISCLAIMER
**I AM NOT RESPONSIBLE FOR ANY USE OR DAMAGE THIS SOFTWARE MAY CAUSE. THIS IS INTENDED FOR EDUCATIONAL PURPOSES ONLY. USE AT YOUR OWN RISK.**
---
### DONATIONS
...are well accepted and will be used to buy the hardware to extend the firmware to other cameras

Please use 
[SEPA (for Europe)](https://www.bunq.me/Lino)
or
[paypal (international)](https://www.paypal.me/linobarreca)

Thank you :)