# Easier timezone management

## Why did I change this

The camera actually has **two** clocks to keep straight: the time itself and the
timezone. When the Yi cloud is enabled, both are decided by the **Yi app**: the
cloud sends the camera the time and the timezone you picked in the app.

Older yi-hack versions had their own, separate timezone setting. If it didn't
match the one in the app, the timestamps produced by the camera disagreed with
each other: the on-video clock (OSD) and the stock recordings followed the app,
while the web interface, logs and yi-hack recordings followed the yi-hack
setting. Easy to get wrong, annoying to notice.

yi-hack-v6 removes the problem: **the camera keeps itself aligned. You never
have to make the two settings match by hand.**

## What you get

- **Cloud enabled** (the normal case): the timezone is taken **automatically
  from the Yi app**. The *Timezone* and *NTP* fields in the web interface are
  shown locked, with a note that the cloud is managing them. Change the
  timezone in the app, and the camera follows.
- **Cloud disabled**: the *Timezone* and *NTP* fields become editable — and the
  timezone **already contains the value inherited from the app**, so nothing
  jumps when you switch. The camera keeps its clock in sync via NTP (this
  happens automatically; the *NTPD* switch just adds a continuously-running
  sync service on top).
- **Fresh camera that never ran with the cloud** (rare): set *Timezone* and
  *NTP server* yourself in the web interface.

## How it works (details)

- The stock cloud software periodically asks the Xiaomi cloud for the device
  info, which includes the timezone you set in the app. yi-hack intercepts that
  answer (without modifying it) and stores the timezone in its own
  configuration, so every part of the firmware uses the same one.
- The stored value is a fixed offset (for example `GMT-1` in POSIX notation for
  GMT+01:00 — the sign is inverted, that's how POSIX works). Daylight-saving
  changes are handled by the cloud itself: when the app/cloud shifts the
  offset, the camera picks the new value up automatically.
- A timezone change is fully applied at the **next reboot** (services read the
  timezone when they start).
- While the cloud is enabled, the built-in NTP service stays off on purpose:
  the cloud already sets the clock, and two things setting the clock at once
  would fight each other.
