# yi-hack-v6 — Provisioning & network boot (CIFS/SMB)

yi-hack-v6 can run **diskless**: instead of keeping the whole firmware payload on the
SD card, the camera mounts a **network share (CIFS/SMB)** and boots the payload from
there. One share serves a whole fleet — update it once, reboot the cameras.

This document explains how to set up the file server and how to provision cameras.

> All IP addresses below use the documentation range `192.0.2.0/24` (RFC 5737).
> Replace them with your own. Never commit real passwords.

---

## 1. The model

There are two halves:

| Half | Lives on | Contains |
|------|----------|----------|
| **base** | camera flash | boot scripts, the rescue web UI, the config that the camera owns |
| **payload** | SD card **or** CIFS share | the binaries (`extra/`) and the centrally-managed config (`config/`) |

The camera **only does something useful when a payload is available** (SD or CIFS).
With no payload it falls back to a minimal "rescue" boot.

### Logical view

The software always reads from fixed paths under `/home/yi-hack/` (`base`, `config`,
`extra`, `output`, `www`). At boot the camera decides what backs `extra`/`output`:

```
mount SD (if present)
mount CIFS (if configured AND reachable AND version-compatible)
logical view:  CIFS if mounted  ->  else SD if mounted  ->  else minimal boot
```

CIFS has **priority** over SD for the payload; the SD, when present, is the
**provisioning / recovery** channel.

### Config: flash is the source of truth, the share is the managed source

All config files live in flash (`/home/yi-hack/config/`). The software never reads
config directly from the share. At boot, config files present on the share are
**copied over** the flash copies ("managed config"). This is how you push settings to
a whole fleet.

Some files are **never** overwritten from the share:

- `camera.conf`, `ptz_presets.conf` — runtime state written by the device.
- `identity.conf`, `hostname` — **per-camera identity** (see §6). A mass push must not
  make two cameras collide.

### Version alignment (important)

The flash **base** and the share/SD **payload** are each versioned. A single version
governs the whole bundle (binaries **and** config schema). The camera applies a
payload's config/binaries **only if** base and payload share the same `MAJOR.MINOR`
(the patch level may differ, e.g. `0.1.0 ↔ 0.1.7` is fine, `0.1 ↔ 0.2` is not).

If they don't match, the camera applies **nothing** from that payload and falls back
to a minimal boot. This is deliberate: pushing `0.2.x` config onto a `0.1.x` base
would mismatch the config schema and could brick the camera. **Update the base first,
then the payload (or keep them in lockstep).**

---

## 2. The file server (Samba) — protocol constraint

The cameras run a very old kernel whose CIFS client only authenticates with
`sec=ntlmssp` over **SMB1 / NT1**. In practice this means:

- The server **must** offer **SMB1 (NT1)** and `ntlm auth = yes`.
- The server's **Samba version must be ≤ 4.13.** Newer Samba (≥ 4.21) negotiates an
  NTLMSSP key-exchange that requires the `arc4` cipher, which these cameras' kernels
  do not provide — the mount fails with `CIFS VFS: could not allocate crypto API arc4`.
  (`dperson/samba` ships Samba 4.13.7 and works.)

> SMB1 is a legacy, security-sensitive protocol. **Isolate the file server**: put it on
> the camera/IoT network segment only, do not publish its ports to other networks,
> require authentication (not guest), and mount the payload **read-only**.

### Authentication, not guest

The share carries managed config that may include secrets (e.g. an MQTT broker
password in `mqtt.conf`). Therefore **do not** serve it as guest. Use one dedicated SMB
account shared by all cameras (e.g. `yicamera`) with a random password. The cameras
hold those credentials in their bootstrap `cifs.conf` (in flash, not on the share).

Generate a password once:

```sh
openssl rand -hex 16
```

---

## 3. File server — docker-compose example

```yaml
services:
  fileserver:
    image: dperson/samba          # Samba 4.13.x — required for these cameras (see §2)
    container_name: fileserver
    restart: always
    # Put this container ONLY on the camera/IoT network, no host port mapping.
    # (Network setup is up to you: a dedicated bridge/macvlan/VLAN, etc.)
    command:
      - "-w"
      - "WORKGROUP"
      - "-g"
      - "server min protocol = NT1"
      - "-g"
      - "client min protocol = NT1"
      - "-g"
      - "ntlm auth = yes"
      # Dedicated SMB account (NOT guest). Use an env var; never hard-code the password.
      - "-u"
      - "${SMB_USER};${SMB_PASSWORD}"
      # share "firmware": browsable=yes readonly=yes guest=NO users=<account>
      - "-s"
      - "firmware;/share;yes;yes;no;${SMB_USER};none;none;Firmware share"
    # Hardening: read-only payload, minimal capabilities, no privilege escalation.
    read_only: false
    cap_drop: ["ALL"]
    cap_add: ["NET_BIND_SERVICE", "SETUID", "SETGID", "DAC_OVERRIDE"]
    security_opt: ["no-new-privileges:true"]
    volumes:
      - ./payload:/share:ro       # the firmware payload tree (read-only into the container)
```

`.env` (do not commit):

```sh
SMB_USER=yicamera
SMB_PASSWORD=<output of: openssl rand -hex 16>
```

Bring it up with `docker compose up -d fileserver`.

### Equivalent `docker run`

```sh
docker run -d --name fileserver --restart always \
  --cap-drop ALL --cap-add NET_BIND_SERVICE --cap-add SETUID --cap-add SETGID --cap-add DAC_OVERRIDE \
  --security-opt no-new-privileges:true \
  -v "$PWD/payload:/share:ro" \
  dperson/samba \
    -w WORKGROUP \
    -g "server min protocol = NT1" -g "client min protocol = NT1" -g "ntlm auth = yes" \
    -u "yicamera;<password>" \
    -s "firmware;/share;yes;yes;no;yicamera;none;none;Firmware share"
```

---

## 4. Share layout (the payload)

The bind-mounted `./payload` directory (served as `//FILESERVER/firmware`) must contain
a `yi-hack/` bundle:

```
payload/                         (== /share in the container, == //FILESERVER/firmware)
  yi-hack/
    version                      # bundle version, e.g. 0.1.0 (governs extra + config)
    extra/                       # binaries, libs, full web UI (the heavy payload)
      bin/  lib/  www/  ...
    config/                      # centrally-managed config copied to flash at boot
      services/
        mqtt.conf                # BROKER_IP/PORT/USER/PASSWORD, topics, ...
        ...
      system.conf
      ...
```

Per-model payloads are also supported: the camera looks for `<MODEL>/yi-hack/...`
first (where `<MODEL>` matches the camera model), then falls back to `yi-hack/...`.

**Do not** put `identity.conf`, `hostname`, `camera.conf` or `ptz_presets.conf` on the
share — those are per-camera/local and are never overwritten from the share.

`version` must match the cameras' base `MAJOR.MINOR` (see §1).

---

## 5. Provisioning a camera (SD → CIFS)

A camera reaches the share using `cifs.conf` in its flash. The simplest way to push
that to a new (or whole fleet of) camera(s) is the **SD card as a provisioning bundle**.

The SD is mounted before the CIFS, so the config it carries is applied first — letting
the camera learn how to reach the share, then mount it.

1. **Prepare an SD provisioning bundle.** On the SD, create:

   ```
   yi-hack/
     version                     # MUST match the cameras' base MAJOR.MINOR (e.g. 0.1.0)
     config/
       cifs.conf
   ```

   `cifs.conf`:

   ```sh
   ENABLED=yes
   HOST=192.0.2.10               # the file server's address
   SHARE=firmware
   USER=yicamera
   PASS=<the SMB password>
   SEC=ntlmssp
   VERS=1.0
   RETRY=10
   RETRY_DELAY=6
   ```

   > The SD must carry a `version` matching the base, otherwise the camera refuses to
   > apply its config (alignment guard, §1). A config-only SD with no version is ignored.

2. **Insert the SD and boot.** The camera copies `cifs.conf` into flash, mounts the
   CIFS share authenticated as `yicamera`, then applies the share's managed config and
   boots the payload.

3. **Remove the SD and reboot.** From now on the camera boots from the CIFS share using
   the `cifs.conf` now stored in its flash. The same SD provisions the next camera.

You can also set `cifs.conf` from the camera's rescue web UI instead of using an SD.

---

## 6. Per-camera identity

Some values must be **unique per camera** and therefore live in `config/identity.conf`,
which is **never** overwritten from the share:

```sh
MQTT_CLIENT_ID=...               # must be unique (a duplicate id disconnects the other)
MQTT_PREFIX=...                  # must be unique (otherwise MQTT topics collide)
HOMEASSISTANT_NAME=...           # the camera's display name
HOMEASSISTANT_IDENTIFIERS=...    # the camera's unique device id
```

Set these per camera (rescue web UI, or locally). They are not part of the shared
managed config.

---

## 7. Updating the fleet

1. Build/stage the new payload and bump `yi-hack/version`.
2. If the `MAJOR.MINOR` changed, update the cameras' **base** first (the base and the
   payload must stay aligned — see §1). A payload whose version doesn't match a camera's
   base is ignored by that camera (it stays on its previous, aligned config + minimal
   boot until its base is updated).
3. Replace the payload on the share.
4. Reboot the cameras (they re-read the share at boot).

---

## 8. Security checklist

- [ ] File server reachable **only** from the camera/IoT segment; no host port mapping.
- [ ] SMB account, **not guest**; random password; payload mounted **read-only**.
- [ ] Container hardened (`cap_drop: ALL` + minimal caps, `no-new-privileges`).
- [ ] No real passwords committed to git (use `.env` / secrets).
- [ ] SMB1 is legacy — its exposure is contained to the isolated segment by design.
