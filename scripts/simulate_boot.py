#!/usr/bin/env python3
# simulate_boot.py - yi-hack-v6
#
# Static boot emulation against the COMPLETE packaged image (stock firmware + v6 overlay),
# i.e. the pre-flash trees left in build/images/<model>/ by scripts/pack_fw.sh:
#
#     build/images/<model>/rootfs/                 -> mounted at /         (jffs2, mtd4)
#     build/images/<model>/home/                   -> mounted at /home     (jffs2, mtd5)
#     build/images/<model>/payload/yi-hack/extra/  -> /home/yi-hack/extra  (SD/CIFS, runtime)
#
# Unlike the old version (which checked the repo source tree, WITHOUT the stock base and
# WITHOUT the build artifacts/farm), this resolves every reference against the *merged*
# filesystem the camera actually sees after flashing, modelling the real mounts.
#
# It walks the v6 boot chain for TWO scenarios:
#     [minimal] no payload  -> /home/yi-hack/extra absent (rescue/minimal boot)
#     [full]    payload      -> /home/yi-hack/extra present (full dispatcher)
#
# and reports, per stage:
#   * referenced files missing from the merged FS                         -> ERROR
#   * commands that do NOT resolve on the effective PATH ("not found")     -> ERROR/WARN
#   * commands resolving to a DANGLING symlink (e.g. the base/bin busybox
#     farm when extra is not mounted)                                      -> diagnosed
#   * WHERE each binary actually resolves: which PATH dir, which real target
#
# Files shipped compressed (<f>.7z, expanded into place by system_init.sh on first boot)
# are treated as present-after-first-boot, not missing.
#
# Run from repo root:  python3 scripts/simulate_boot.py [model]   (default model: y20)
#   -> writes simulated_boot.log, exits non-zero if any ERROR was found.

import os, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL = sys.argv[1] if len(sys.argv) > 1 else "y20"
IMG = os.path.join(REPO, "build/images", MODEL)
ROOTFS = os.path.join(IMG, "rootfs")
HOME = os.path.join(IMG, "home")
PAYLOAD_EXTRA = os.path.join(IMG, "payload/yi-hack/extra")

# busybox init's default PATH when none is set in inittab.
INIT_PATH = ["/sbin", "/usr/sbin", "/bin", "/usr/bin"]

log_lines = []
errors = 0
warns = 0
def out(s=""): log_lines.append(s)


# ---------------------------------------------------------------------------
# Merged filesystem model
# ---------------------------------------------------------------------------
class FS:
    """Maps absolute camera paths to locations in the packaged image trees,
    modelling the mounts. `payload` toggles whether /home/yi-hack/extra is mounted."""

    def __init__(self, payload_mounted):
        self.payload = payload_mounted

    def to_image(self, abspath):
        """Return the on-disk location of an absolute camera path, or None if it maps
        to an area that is not mounted/present in this scenario (e.g. extra when no payload,
        or a tmpfs runtime path)."""
        abspath = os.path.normpath(abspath)
        # /home/yi-hack/extra is a runtime symlink to the payload source.
        if abspath == "/home/yi-hack/extra" or abspath.startswith("/home/yi-hack/extra/"):
            if not self.payload:
                return None
            rest = abspath[len("/home/yi-hack/extra"):].lstrip("/")
            return os.path.join(PAYLOAD_EXTRA, rest)
        # /home/yi-hack/www is a runtime symlink built by build_view.sh:
        #   full boot -> extra/www (payload) ; minimal boot -> base/www-min (flash rescue).
        if abspath == "/home/yi-hack/www" or abspath.startswith("/home/yi-hack/www/"):
            rest = abspath[len("/home/yi-hack/www"):].lstrip("/")
            if self.payload:
                return os.path.join(PAYLOAD_EXTRA, "www", rest)
            return os.path.join(HOME, "yi-hack/base/www-min", rest)
        if abspath == "/home" or abspath.startswith("/home/"):
            return os.path.join(HOME, abspath[len("/home/"):]) if abspath != "/home" else HOME
        # tmpfs / runtime-only areas: not part of the static image
        if abspath.startswith(("/tmp/", "/dev/", "/proc/", "/sys/", "/var/", "/run/")):
            return None
        return os.path.join(ROOTFS, abspath.lstrip("/"))

    def lexists(self, abspath):
        """Does the path exist (without following the final symlink)?
        Accounts for first-boot .7z expansion: <f> counts as present if <f>.7z ships."""
        loc = self.to_image(abspath)
        if loc is None:
            return False
        if os.path.lexists(loc):
            return True
        if os.path.lexists(loc + ".7z"):   # shipped compressed, expanded on first boot
            return True
        return False

    def realtarget(self, abspath):
        """Follow a symlink chain through the merged FS.
        Returns (kind, detail):
          ('file', image_location)      - resolves to a real regular file/dir present now
          ('compressed', image_loc.7z)  - resolves to a file shipped as .7z (first-boot expand)
          ('dangling', target_abspath)  - symlink whose target is absent/unmounted
          ('missing', None)             - the path itself does not exist
        """
        loc = self.to_image(abspath)
        if loc is None:
            return ("dangling", abspath)
        seen = set()
        cur_abs = abspath
        cur_loc = loc
        while True:
            if cur_loc in seen:
                return ("dangling", cur_abs)   # symlink loop
            seen.add(cur_loc)
            if os.path.islink(cur_loc):
                tgt = os.readlink(cur_loc)
                cur_abs = tgt if tgt.startswith("/") else os.path.normpath(
                    os.path.join(os.path.dirname(cur_abs), tgt))
                nxt = self.to_image(cur_abs)
                if nxt is None:
                    return ("dangling", cur_abs)
                cur_loc = nxt
                continue
            if os.path.exists(cur_loc):
                return ("file", cur_loc)
            if os.path.lexists(cur_loc + ".7z"):
                return ("compressed", cur_loc + ".7z")
            return ("dangling", cur_abs)

    def resolve_cmd(self, cmd, path_list):
        """Mimic shell PATH lookup. Walk path_list; a candidate that is a dangling symlink
        is skipped (execve would ENOENT) but recorded. Returns dict with resolution."""
        skipped_dangling = []
        for d in path_list:
            cand = os.path.join(d, cmd)
            loc = self.to_image(cand)
            if loc is None or not os.path.lexists(loc):
                # also allow first-boot-expanded binaries
                if loc is not None and os.path.lexists(loc + ".7z"):
                    return {"found_dir": d, "kind": "compressed",
                            "target": loc + ".7z", "skipped": skipped_dangling}
                continue
            kind, detail = self.realtarget(cand)
            if kind in ("file", "compressed"):
                return {"found_dir": d, "kind": kind, "target": detail, "skipped": skipped_dangling}
            else:  # dangling
                skipped_dangling.append((d, detail))
        return {"found_dir": None, "kind": "notfound", "target": None, "skipped": skipped_dangling}


# ---------------------------------------------------------------------------
# Reporting primitives
# ---------------------------------------------------------------------------
def stage(title):
    out("")
    out("  " + title)

def short(loc):
    """Trim an image path for readable output."""
    if loc is None:
        return "-"
    for base, tag in ((PAYLOAD_EXTRA, "payload:extra"), (HOME, "home"), (ROOTFS, "rootfs")):
        if loc.startswith(base):
            return f"{tag}:{loc[len(base):].lstrip('/')}"
    return loc

def check_file(fs, abspath, label="", critical=True):
    """Assert a referenced file exists in the merged FS."""
    global errors, warns
    if fs.lexists(abspath):
        kind, detail = fs.realtarget(abspath)
        note = ""
        if kind == "compressed":
            note = "  (ships .7z, expanded first boot)"
        elif kind == "dangling":
            # path exists (lexists true) but symlink target unresolved
            out(f"      DANGLING {abspath} -> {detail}   {label}")
            if critical:
                errors += 1
            else:
                warns += 1
            return
        out(f"      ok   {abspath}  [{short(detail)}]{note}  {label}")
    else:
        out(f"      MISS {abspath}   <-- MISSING IN IMAGE   {label}")
        if critical:
            errors += 1
        else:
            warns += 1

def check_cgi_shebang(fs, cgi_abspath, critical=True, label=""):
    """A CGI invoked by httpd is exec'd; the kernel reads its #! interpreter and runs it.
    Verify the interpreter path resolves in the merged FS (catches stale hardcoded paths
    like the v5 /tmp/sd/... shebangs that break ONVIF on a diskless v6 boot)."""
    global errors, warns
    loc = fs.to_image(cgi_abspath)
    if loc is None or not os.path.lexists(loc):
        out(f"      MISS {cgi_abspath}   <-- CGI MISSING   {label}")
        errors += 1 if critical else 0
        warns += 0 if critical else 1
        return
    try:
        with open(loc, "rb") as fh:
            first = fh.readline().decode("latin-1").rstrip("\n")
    except OSError:
        first = ""
    if not first.startswith("#!"):
        out(f"      --   {cgi_abspath}  (no shebang; data file)  {label}")
        return
    interp = first[2:].split()[0]
    kind, detail = fs.realtarget(interp)
    if kind in ("file", "compressed"):
        out(f"      ok   {os.path.basename(cgi_abspath):<16} #!{interp}  [{short(detail)}]  {label}")
    else:
        out(f"      FAIL {os.path.basename(cgi_abspath):<16} #!{interp}  <-- INTERPRETER NOT FOUND "
            f"({'unmounted/absent' if detail else 'missing'})  {label}")
        if critical:
            errors += 1
        else:
            warns += 1

def check_exec(fs, abspath, label=""):
    """For a script/binary invoked by absolute path (not sourced, not via PATH): it must
    exist AND have an execute bit, else execve() fails with EACCES at boot."""
    global errors
    if not fs.lexists(abspath):
        out(f"      MISS {abspath}   <-- MISSING IN IMAGE   {label}")
        errors += 1
        return
    kind, detail = fs.realtarget(abspath)
    if kind not in ("file", "compressed"):
        out(f"      DANGLING {abspath} -> {detail}   {label}")
        errors += 1
        return
    try:
        mode = os.stat(detail).st_mode
        if mode & 0o111:
            out(f"      ok   {abspath}  [{short(detail)}, +x]  {label}")
        else:
            out(f"      NOEXEC {abspath}  [{short(detail)}, mode {oct(mode & 0o777)}]"
                f"  <-- NOT EXECUTABLE (execve EACCES)  {label}")
            errors += 1
    except OSError:
        out(f"      ?    {abspath}  (stat failed)  {label}")

def check_cmd(fs, cmd, path_list, critical=True, label=""):
    """Resolve a command on PATH and report where it lands."""
    global errors, warns
    r = fs.resolve_cmd(cmd, path_list)
    skipnote = ""
    if r["skipped"]:
        skipnote = "  (skipped dangling: " + ", ".join(d for d, _ in r["skipped"]) + ")"
    if r["kind"] in ("file", "compressed"):
        extra = "  (.7z)" if r["kind"] == "compressed" else ""
        out(f"      ok   {cmd:<14} -> {r['found_dir']}  [{short(r['target'])}]{extra}{skipnote}  {label}")
    else:
        out(f"      FAIL {cmd:<14} -> NOT FOUND on PATH{skipnote}  {label}")
        if critical:
            errors += 1
        else:
            warns += 1


# ---------------------------------------------------------------------------
# Boot chain (shared by both scenarios). `s20_path` and `payload` differ per scenario.
# ---------------------------------------------------------------------------
def run_scenario(name, payload_mounted):
    fs = FS(payload_mounted)
    out("")
    out("#" * 78)
    out(f"# SCENARIO: {name}   (payload {'MOUNTED at /home/yi-hack/extra' if payload_mounted else 'ABSENT'})")
    out("#" * 78)

    # -- init / rcS --
    stage("kernel -> busybox init -> inittab ::sysinit -> rcS -> S[0-9][0-9]*  (PATH = init default)")
    check_file(fs, "/etc/inittab", "stock")
    check_file(fs, "/etc/init.d/rcS", "stock")
    check_exec(fs, "/etc/init.d/S01udev", "overlay (run by rcS)")
    check_exec(fs, "/etc/init.d/S20yi-hack", "overlay (run by rcS)")

    # -- S01udev -> system_init.sh + base/init.sh --
    stage("S01udev: mount /home, run system_init.sh + base/init.sh  (PATH = init default)")
    check_exec(fs, "/home/yi-hack/base/script/system_init.sh", "run by S01udev")
    check_file(fs, "/home/base/init.sh", "stock")
    out("    system_init.sh first-boot extraction + helpers (uses ABSOLUTE /home/base/tools/7za):")
    check_file(fs, "/home/base/tools/7za", "needed to expand *.7z on first boot")
    for f in ("cloudAPI", "cloudAPI_fake", "default.script", "wifidhcp.sh"):
        check_file(fs, f"/home/yi-hack/base/script/{f}")
    out("    commands system_init.sh relies on PATH for (find/awk/sed/mv/cp/rm/mkdir/cat):")
    for c in ("find", "awk", "sed", "mkdir", "mv", "cp", "rm", "cat"):
        check_cmd(fs, c, INIT_PATH)

    stage("base/init.sh [stock] -> app/init.sh [stock]: modules, tmpfs, mount SD, WiFi up")
    check_file(fs, "/home/app/init.sh", "stock")
    check_file(fs, "/home/app/.camver", "stock (MODEL_SUFFIX source)")
    out("    (WiFi driver + HW modules loaded; SD mounted at /tmp/sd if present)")

    # -- S20yi-hack --
    s20_path = ["/home/base/tools", "/home/app/localbin"] + INIT_PATH
    stage("S20yi-hack: PATH = " + ":".join(s20_path))
    out("    scripts S20 invokes by absolute path (must be +x):")
    for f in ("apply_config.sh", "wifi_up.sh", "mount_cifs.sh", "build_view.sh", "system.sh"):
        check_exec(fs, f"/home/yi-hack/base/script/{f}")
    check_exec(fs, "/home/yi-hack/base/script/wifidhcp.sh", "run by wifi_up")
    for f in ("get_config.sh", "version_compat.sh"):
        check_file(fs, f"/home/yi-hack/base/script/{f}", "sourced (no +x needed)")
    check_file(fs, "/home/yi-hack/config/cifs.conf")
    check_file(fs, "/home/yi-hack/config/wifi.conf", "WiFi override (empty -> mtdblock2 fallback)")
    check_file(fs, "/home/yi-hack/config/output.conf")
    check_file(fs, "/home/app/localko/cifs.ko", "stock (+ md4.ko + hmac.ko)")
    out("    wifi_up.sh: associate WiFi BEFORE mount_cifs (creds mtdblock2[28/92] / wifi.conf):")
    for c in ("wpa_supplicant", "wpa_passphrase", "wpa_cli"):
        check_cmd(fs, c, s20_path, label="wpa (base/tools; .7z until first boot)")
    check_cmd(fs, "udhcpc", s20_path, label="DHCP")

    if payload_mounted:
        # build_view exit 0 -> system.sh dispatcher
        stage("[build_view exit 0] system.sh DISPATCHER  (sources env.sh; full busybox via base/bin farm)")
        # env.sh PATH when extra mounted: base/bin first (farm -> full busybox)
        full_path = ["/home/yi-hack/base/bin", "/home/yi-hack/extra/bin",
                     "/usr/bin", "/usr/sbin", "/bin", "/sbin",
                     "/home/base/tools", "/home/app/localbin", "/home/base"]
        check_file(fs, "/home/yi-hack/base/script/env.sh")
        check_file(fs, "/home/yi-hack/extra/bin/busybox", "full busybox (farm target)")
        check_file(fs, "/home/yi-hack/extra/../version", "bundle version (system.sh reads extra/../version)")
        out("    config read via get_config:")
        for c in ("system.conf", "camera.conf", "output.conf", "identity.conf"):
            check_file(fs, f"/home/yi-hack/config/{c}")
        check_file(fs, "/home/yi-hack/config/services/mqtt.conf")
        out("    flash helpers invoked by the dispatcher:")
        for h in ("check_conf.sh", "wd_rtsp.sh", "conf2mqtt.sh", "ptz_presets.sh",
                  "clean_records.sh", "ftppush.sh", "check_update.sh", "configure_wifi.sh"):
            check_file(fs, f"/home/yi-hack/base/script/{h}")
        check_file(fs, "/home/yi-hack/base/script/mqtt_advertise/startup.sh")
        out("    httpd + applets resolve through the farm (base/bin -> extra/bin/busybox):")
        for c in ("httpd", "telnetd", "sh", "head", "readlink"):
            check_cmd(fs, c, full_path)
        out("    SSH (dropbear: real binaries in base/bin) and payload daemons (launched by name):")
        check_cmd(fs, "dropbear", full_path)
        for c in ("rRTSPServer", "h264grabber", "mqttv4", "ipc_cmd",
                  "onvif_notify_server", "ipc2file", "wsd_simple_server"):
            check_cmd(fs, c, full_path, label="payload daemon")
        out("    ONVIF SOAP = CGI: httpd routes /onvif/* to www/onvif/* (not a PATH daemon).")
        out("    Each CGI service file's #! interpreter must resolve via the www logical view:")
        check_file(fs, "/home/yi-hack/www/onvif/onvif_simple_server", "ONVIF CGI (via www->extra/www)")
        for svc in ("device_service", "events_service", "media_service", "ptz_service"):
            check_cgi_shebang(fs, f"/home/yi-hack/extra/www/onvif/{svc}", label="ONVIF CGI")
        out("    stock cloud daemons (launched via cd /home/app; ./<bin>):")
        for b in ("dispatch", "rmm", "cloud", "mp4record", "p2p_tnp", "oss", "watch_process"):
            check_file(fs, f"/home/app/{b}", "stock", critical=False)
    else:
        # build_view exit 1 -> minimal boot branch in S20 (runs under S20's PATH!)
        stage("[build_view exit 1] MINIMAL BOOT  (runs under S20 PATH, NOT a login shell)")
        out("    rescue web UI + telnet (the ONLY recovery channels if this branch runs):")
        check_file(fs, "/home/yi-hack/base/www-min/index.html", "rescue UI root")
        for c in ("status.sh", "get.sh", "save.sh", "cifstest.sh", "reboot.sh", "rescue_lib.sh"):
            check_file(fs, f"/home/yi-hack/base/www-min/cgi-bin/{c}", "rescue CGI")
        out("    commands the minimal-boot branch launches, resolved on S20's PATH:")
        check_cmd(fs, "httpd", s20_path, label="rescue web UI")
        check_cmd(fs, "telnetd", s20_path, label="recovery shell")
        out("    SSH recovery: dropbear launched by ABSOLUTE path (base/bin not on S20 PATH):")
        check_file(fs, "/home/yi-hack/base/bin/dropbear", "SSH recovery (-> dropbearmulti)")
        out("    host keys: -R generates on demand at compiled path /home/yi-hack/config/dropbear/")
        out("      --   /home/yi-hack/config/dropbear  (created at boot via mkdir -p; flash, writable)")
        out("    stock cloud daemons (cd /home/app; ./<bin>) unless privacy=on:")
        for b in ("dispatch", "rmm", "cloud", "mp4record", "p2p_tnp", "oss", "watch_process"):
            check_file(fs, f"/home/app/{b}", "stock", critical=False)

    # -- login shells (telnet / ssh) source /etc/profile --
    login_path = (["/home/yi-hack/base/bin", "/home/yi-hack/extra/bin",
                   "/usr/bin", "/usr/sbin", "/bin", "/sbin",
                   "/home/base/tools", "/home/app/localbin", "/home/base"]
                  if payload_mounted else
                  ["/usr/bin", "/usr/sbin", "/bin", "/sbin",
                   "/home/base/tools", "/home/app/localbin", "/home/base",
                   "/home/yi-hack/base/bin"])
    stage("login shell (telnet/ssh) sources /etc/profile  -> PATH = " + ":".join(login_path))
    check_file(fs, "/etc/profile")
    out("    sanity of common applets a recovering operator needs:")
    for c in ("sh", "ls", "cat", "vi", "mount", "flashcp", "tar", "nc"):
        check_cmd(fs, c, login_path)
    out(f"    banner reads: cat /home/yi-hack/extra/../version  -> "
        f"{'resolves to bundle version' if payload_mounted else 'extra ABSENT: cat fails (cosmetic)'}")


# ---------------------------------------------------------------------------
out("=" * 78)
out(f" yi-hack-v6 - SIMULATED BOOT on packaged image  (model: {MODEL})")
out(f" image: build/images/{MODEL}/{{rootfs,home}} + payload")
out(" Generated by scripts/simulate_boot.py")
out("=" * 78)

if not os.path.isdir(ROOTFS) or not os.path.isdir(HOME):
    out("")
    out(f" ERROR: {IMG}/{{rootfs,home}} not found.")
    out(" Run ./build_all.sh all  (or pack) first; pack_fw.sh leaves the trees for inspection.")
    print("\n".join(log_lines))
    sys.exit(2)

if not os.path.isdir(PAYLOAD_EXTRA):
    out("")
    out(f" NOTE: {PAYLOAD_EXTRA} not found - 'full' scenario will report extra as absent.")

run_scenario("minimal boot (no SD/CIFS payload)", payload_mounted=False)
run_scenario("full boot (payload present)", payload_mounted=True)

out("")
out("=" * 78)
out(f" RESULT: {errors} error(s), {warns} warning(s)")
out(" Legend: ok=resolves now | .7z=expanded on first boot | DANGLING/FAIL=boot risk")
out("=" * 78)

with open(os.path.join(REPO, "simulated_boot.log"), "w") as f:
    f.write("\n".join(log_lines) + "\n")
print("\n".join(log_lines))
sys.exit(1 if errors else 0)
