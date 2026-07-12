# The redesigned web interface

## Why did I change this

The old interface was a single giant "Config" page plus a dozen loose ones, and
it let you save combinations that simply don't work on this camera: NTP fighting
the cloud over the clock, a recorder with no video stream to record, ONVIF
announcing a resolution that isn't published. You only found out later, when
something silently didn't work.

The new interface is organized around what you want to do, and it **knows the
rules**: options that depend on each other follow each other, impossible
combinations are not offered, and anything you can't change tells you *why*.

## What you get

- A **Status** dashboard: what's running, where the Yi-Hack firmware is loaded
  from (SD card or network share), where recordings and logs go, service states.
- **Live view**: snapshot preview straight from the camera (no cloud, no app),
  with pan/tilt controls on motorized models.
- **Recordings**: browse the recorded clips by hour and play them in the browser.
- **Camera settings**: the same controls as the Yi app (detection, LED, IR,
  microphone, …), applied immediately — cloud not required.
- **Recording (NVR)**: one clear choice — off, stock recorder, or the private
  native recorder — with only the combinations that actually work.
- **Network & shares**: WiFi, hostname, and the two network shares (firmware,
  outputs) with built-in connection tests.
- **Services**: RTSP, ONVIF, snapshots, MQTT / Home Assistant, and how you reach
  the camera (web/SSH/telnet/FTP) — with a guard so you can't lock yourself out.
- **System**: cloud on/off, time & timezone, backup/restore, firmware update,
  reboot and reset.
- **Diagnostics**: logs (boot, services, kernel), live system state, connection
  tests, and a one-click **diagnostics bundle** (passwords redacted) to attach
  to bug reports.

## Who owns a setting

Some settings aren't yours to change, and the interface says so with a small tag
instead of failing silently:

| Tag | Meaning |
|---|---|
| ☁ *from Yi app* | While the cloud is enabled, this follows the Yi app (time & timezone). Disable the cloud to edit it. |
| 🔒 *fixed for this model* | Locked at build time because this camera model can't support it (not enough memory, no motor, …). |
| ⇩ *managed centrally* | The file comes from the network share at every boot ([shared configuration](shared-configuration.md)) — edit it there. |

## Notes

- Most saved changes are applied at the **next reboot** (the interface says so
  after saving). Camera settings apply immediately.
- Light and dark theme, following your system preference (toggle in the sidebar).
- The interface is built with standard libraries (Bootstrap, Alpine.js) and
  plain, unminified files — easy to read and modify on the share. The libraries
  are downloaded at build time with pinned checksums, like every other source
  in this project; see `src/www/httpd/htdocs/vendor/VENDOR.md`. No build tools
  needed.
- The recovery ("rescue") interface that appears when the camera boots without
  its full firmware is separate and unchanged — see
  [recovery mode](recovery-mode.md).
