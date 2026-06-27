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

import os, sys, subprocess, shutil

HAVE_OBJDUMP = shutil.which("objdump") is not None

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

def err(msg):
    """Record a boot-fatal problem - rendered LOUD and UPPERCASE so it cannot be missed
    in the wall of 'ok' lines (a swallowed NOEXEC on base/init.sh once cost us hours)."""
    global errors
    errors += 1
    out("      " + "!" * 8 + " ERROR " + "!" * 8 + "  " + msg.upper())

def warn(msg):
    global warns
    warns += 1
    out("      ~~ WARNING ~~  " + msg)


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
            (err if critical else warn)(f"DANGLING SYMLINK {abspath} -> {detail}  {label}")
            return
        out(f"      ok   {abspath}  [{short(detail)}]{note}  {label}")
    else:
        (err if critical else warn)(f"MISSING IN IMAGE {abspath}  {label}")

def check_cgi_shebang(fs, cgi_abspath, critical=True, label=""):
    """A CGI invoked by httpd is exec'd; the kernel reads its #! interpreter and runs it.
    Verify the interpreter path resolves in the merged FS (catches stale hardcoded paths
    like the v5 /tmp/sd/... shebangs that break ONVIF on a diskless v6 boot)."""
    global errors, warns
    loc = fs.to_image(cgi_abspath)
    if loc is None or not os.path.lexists(loc):
        (err if critical else warn)(f"CGI MISSING {cgi_abspath}  {label}")
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
        (err if critical else warn)(f"CGI INTERPRETER NOT FOUND {os.path.basename(cgi_abspath)} "
                                    f"#!{interp} ({'unmounted/absent' if detail else 'missing'})  {label}")

def check_elf_libs(fs, binpath, ld_dirs, label=""):
    """Resolve an ELF's NEEDED shared libraries in the runtime LD search path. A binary can
    resolve on PATH yet fail at exec because a NEEDED lib is missing or a dangling symlink
    (e.g. /lib/libutil.so.0 -> /tmp/sd/... ). ld_dirs = LD_LIBRARY_PATH dirs + /lib,/usr/lib.
    Follows symlinks through the merged FS and accepts libs shipped compressed (.7z)."""
    global errors, warns
    if not HAVE_OBJDUMP:
        return
    loc = fs.to_image(binpath)
    if loc is None or not os.path.exists(loc):
        return  # binary absent/compressed here — existence covered by other checks
    try:
        dump = subprocess.check_output(["objdump", "-p", loc], stderr=subprocess.DEVNULL, text=True)
    except Exception:
        return
    needed = [ln.split()[1] for ln in dump.splitlines() if "NEEDED" in ln]
    if not needed:
        return
    missing = []
    for lib in needed:
        ok = False
        for d in ld_dirs:
            cand = os.path.join(d, lib)
            if not fs.lexists(cand):
                continue
            kind, _ = fs.realtarget(cand)
            if kind in ("file", "compressed"):
                ok = True
                break
        if not ok:
            missing.append(lib)
    if missing:
        err(f"NEEDED LIB UNRESOLVED (won't load at exec) {os.path.basename(binpath)}: "
            f"{', '.join(missing)}  {label}")
    else:
        out(f"      ok   {os.path.basename(binpath):<18} all {len(needed)} NEEDED libs resolve  {label}")

def check_exec(fs, abspath, label=""):
    """For a script/binary invoked by absolute path (not sourced, not via PATH): it must
    exist AND have an execute bit, else execve() fails with EACCES at boot."""
    if not fs.lexists(abspath):
        err(f"MISSING IN IMAGE {abspath}  {label}")
        return
    kind, detail = fs.realtarget(abspath)
    if kind not in ("file", "compressed"):
        err(f"DANGLING SYMLINK {abspath} -> {detail}  {label}")
        return
    try:
        mode = os.stat(detail).st_mode
        if mode & 0o111:
            out(f"      ok   {abspath}  [{short(detail)}, +x]  {label}")
        else:
            err(f"NOT EXECUTABLE - execve EACCES, DEAD BOOT - {abspath} "
                f"[{short(detail)}, mode {oct(mode & 0o777)}]  {label}")
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
        (err if critical else warn)(f"COMMAND NOT FOUND ON PATH: {cmd}{skipnote}  {label}")


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
    check_exec(fs, "/home/base/init.sh", "stock - run by S01udev via absolute path (needs +x)")
    out("    system_init.sh first-boot extraction + helpers (uses ABSOLUTE /home/base/tools/7za):")
    check_file(fs, "/home/base/tools/7za", "needed to expand *.7z on first boot")
    for f in ("cloudAPI", "cloudAPI_fake", "default.script", "wifidhcp.sh"):
        check_file(fs, f"/home/yi-hack/base/script/{f}")
    out("    commands system_init.sh relies on PATH for (find/awk/sed/mv/cp/rm/mkdir/cat):")
    for c in ("find", "awk", "sed", "mkdir", "mv", "cp", "rm", "cat"):
        check_cmd(fs, c, INIT_PATH)

    stage("base/init.sh [stock] -> app/init.sh [stock]: modules, tmpfs, mount SD, WiFi up")
    check_exec(fs, "/home/app/init.sh", "stock - run by base/init.sh via absolute path (needs +x)")
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
        check_exec(fs, "/home/yi-hack/base/script/mqtt_advertise/startup.sh", "run by system.sh (must be +x)")
        out("    httpd + applets resolve through the farm (base/bin -> extra/bin/busybox):")
        for c in ("httpd", "telnetd", "sh", "head", "readlink"):
            check_cmd(fs, c, full_path)
        out("    SSH (dropbear: real binaries in base/bin) and payload daemons (launched by name):")
        check_cmd(fs, "dropbear", full_path)
        for c in ("rRTSPServer", "h264grabber", "mqttv4", "ipc_cmd",
                  "onvif_notify_server", "ipc2file", "wsd_simple_server"):
            check_cmd(fs, c, full_path, label="payload daemon")
        out("    ELF NEEDED shared libs resolve in the LD path (LD_LIBRARY_PATH + /lib,/usr/lib):")
        LD_FULL = ["/lib", "/usr/lib", "/home/lib", "/home/app/locallib", "/home/hisiko/hisilib",
                   "/home/yi-hack/extra/lib", "/home/yi-hack/base/lib"]
        check_elf_libs(fs, "/home/yi-hack/base/bin/dropbearmulti", LD_FULL, "dropbear/SSH")
        for b in ("rRTSPServer", "mqttv4", "onvif_notify_server", "h264grabber"):
            check_elf_libs(fs, f"/home/yi-hack/extra/bin/{b}", LD_FULL, "payload service")
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
        check_exec(fs, "/home/yi-hack/config/dropbear", "key dir (ships in home image; -R writes keys here)")
        # dropbear's NEEDED libs must resolve in the minimal-boot LD path (no extra/lib: payload absent).
        check_elf_libs(fs, "/home/yi-hack/base/bin/dropbearmulti",
                       ["/home/lib", "/home/app/locallib", "/home/hisiko/hisilib", "/lib", "/usr/lib"],
                       "dropbear/SSH (minimal)")
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
    out("    banner reads: cat /home/yi-hack/version  (profile; payload-independent)")
    check_file(fs, "/home/yi-hack/version", "banner version (profile reads /home/yi-hack/version)")


# ---------------------------------------------------------------------------
# BOOT I/O TRACE: open the real boot scripts in execution order and simulate the
# kernel mount table + the boot-log (stdout/stderr) redirect chain. This answers the
# question the static checks cannot: WHEN is /tmp/sd mounted, and is it mounted at the
# moment S20yi-hack tries to persist the official yi-boot.log (DEBUG_LOG=yes path)?
# ---------------------------------------------------------------------------
import re

def _read_lines(path):
    try:
        with open(path, encoding="latin-1") as fh:
            return fh.readlines()
    except OSError:
        return None

def trace_boot_io():
    out("")
    out("#" * 78)
    out("# BOOT I/O TRACE - virtual mount table + boot-log (stdout/stderr) redirect")
    out("# Q: is /tmp/sd mounted when S20 persists the official yi-boot.log?")
    out("#" * 78)

    mtab = {}            # mountpoint -> source device/fs  (global kernel mount table)
    devs = {}            # device -> mountpoint  (to detect a 2nd mount of the same device)
    fd = ["console/ttyAMA0 (volatile, lost on reboot)"]   # where stdout/stderr points

    def _clean(s):
        # drop trailing redirections / list operators so the mount/umount parser sees only args
        for cut in ("2>", "&&", "||", ";", "|", ">>", ">"):
            i = s.find(cut)
            if i != -1 and not s[:i].rstrip().endswith("exec"):
                s = s[:i]
        return s.strip()

    def _mount_args(rest):
        # rest = everything after the word 'mount'. Strip -t TYPE / -o OPTS, collect positionals + opts string.
        toks = rest.split()
        opts, pos = "", []
        i = 0
        while i < len(toks):
            t = toks[i]
            if t in ("-t", "-o"):
                if t == "-o" and i + 1 < len(toks): opts += toks[i+1]
                i += 2; continue
            if t.startswith("-"):
                i += 1; continue
            pos.append(t); i += 1
        return pos, opts

    def step(script, raw):
        s = s0 = raw.strip()
        if not s or s.startswith("#"):
            return
        # (a) CONFIG READS: every get_config <section>.KEY on the line -> which flag, which file.
        for ref in re.findall(r'get_config\s+([A-Za-z0-9_./]+)', s0):
            sect = ref.split(".", 1)[0]
            out(f"  [{script:13}] CONFIG READ  {ref:28} <- config/{sect}.conf")
        # (b) boot-log redirect
        if s.startswith("exec") and ">>" in s:
            tgt = s.split(">>", 1)[1].split()[0]
            fd[0] = tgt
            out(f"  [{script:13}] LOG REDIRECT exec >> {tgt}   <-- stdout/stderr (boot-log) now writes HERE")
            return
        sc = _clean(s)
        if sc.startswith("umount"):
            mp = [t for t in sc.split()[1:] if not t.startswith("-")]
            mp = mp[-1] if mp else "?"
            if mp in mtab:
                devs.pop(mtab[mp], None); mtab.pop(mp, None)
                out(f"  [{script:13}] umount {mp}")
            else:
                out(f"  [{script:13}] umount {mp}   (was NOT mounted - no-op)")
            return
        if sc.startswith("mount"):
            pos, opts = _mount_args(sc[len("mount"):])
            if "remount" in opts:
                mp = pos[-1] if pos else "?"
                ok = mp in mtab
                out(f"  [{script:13}] MOUNT remount {mp}   ({'ok, was mounted' if ok else 'FAIL: NOT mounted'})")
                return
            src = pos[0] if pos else "?"
            mp  = pos[1] if len(pos) > 1 else (pos[0] if pos else "?")
            bind = "bind" in opts
            if src.startswith("/dev/") and src in devs and not bind:
                out(f"  [{script:13}] MOUNT {src} -> {mp}   *** REFUSED: {src} already mounted at "
                    f"{devs[src]} (same device twice) -> {mp} STAYS UNMOUNTED ***")
                return
            mtab[mp] = src
            if src.startswith("/dev/"): devs[src] = mp
            out(f"  [{script:13}] MOUNT {src} -> {mp}{' [bind]' if bind else ''}    (mounted now: {sorted(mtab)})")
            return
        if sc.startswith("checkdisk"):
            out(f"  [{script:13}] checkdisk  (stock: fdisk /dev/mmcblk0; may transiently mount/umount /tmp/sd)")
            return
        # (c) the /tmp/sd persistence GUARD
        if "grep" in s0 and " /tmp/sd " in s0 and "mount" in s0:
            ok = "/tmp/sd" in mtab
            out(f"  [{script:13}] GUARD 'mount|grep \" /tmp/sd \"' = {ok}  =>  "
                f"{'persist yi-boot.log to SD' if ok else 'NOT mounted -> RAM-only -> NO SD log'}")
            return
        # (d) file I/O - but only to NOTABLE paths (boot-log, /tmp/sd, wifi markers, config,
        # core_pattern), so echo-string noise is filtered out. Strip stderr redirects (2>... are
        # NOT writes - they only silence errors) and take the first command of a compound line.
        def _p(x): return x.strip().strip('";).')
        io = re.sub(r'2>&1|2>\S+|&>\S+', '', s0)
        io = re.split(r'\s*(?:&&|\|\||;)\s*', io)[0].strip()   # first command only
        toks = io.split(); c0 = toks[0] if toks else ""
        NOTABLE = re.compile(r'yi-boot\.log|/tmp/sd|ramlog|/tmp/(?:MTK|BCM)|\.conf|core_pattern|/dbgsd')
        nt = lambda *ps: any(p and NOTABLE.search(p) for p in ps)
        if c0 == "touch":
            f = next((t for t in toks[1:] if not t.startswith("-")), "")
            if nt(f): out(f"  [{script:13}] touch {_p(f)}   (create-if-absent; does NOT truncate)")
            return
        if c0 in ("cat", "echo", "printf", "dd") and ">" in io:
            dst = io.split(">", 1)[1].split()[0]
            if nt(dst):
                src = toks[1] if (c0 == "cat" and len(toks) > 1 and not toks[1].startswith("-")) else ""
                out(f"  [{script:13}] {'COPY' if src else 'WRITE'} {(_p(src)+' -> ') if src else '-> '}{_p(dst)}")
            return
        if c0 in ("cp", "mv"):
            a = [t for t in toks[1:] if not t.startswith("-")]
            if len(a) >= 2 and nt(a[0], a[-1]):
                out(f"  [{script:13}] {'COPY' if c0=='cp' else 'MOVE'} {_p(a[0])} -> {_p(a[-1])}")
            return
        if c0 == ".":
            if len(toks) > 1: out(f"  [{script:13}] SOURCE {_p(toks[1])}   (read + run)")
            return
        m = re.search(r'(?:^|\s)1?>>?\s*(/[^\s&|;<>]+)', io)
        if m and nt(m.group(1)) and not s.startswith("exec"):
            out(f"  [{script:13}] WRITE -> {_p(m.group(1))}"); return

    SCR = os.path.join(HOME, "yi-hack/base/script")
    out("")
    out("-- Process tree A: S01udev -> system_init.sh -> base/init.sh -> app/init.sh  (shared fd) --")
    for name, path in (("S01udev",      os.path.join(ROOTFS, "etc/init.d/S01udev")),
                       ("system_init",  os.path.join(SCR, "system_init.sh")),
                       ("base/init.sh", os.path.join(HOME, "base/init.sh")),
                       ("app/init.sh",  os.path.join(HOME, "app/init.sh"))):
        lines = _read_lines(path)
        if lines is None:
            out(f"  [{name:13}] <NOT FOUND: {path}>"); continue
        for ln in lines:
            step(name, ln)

    out("")
    out("-- Process B: S20yi-hack  (rcS child: fresh fd = console; inherits global mount table) --")
    fd[0] = "console/ttyAMA0 (volatile)"
    for ln in (_read_lines(os.path.join(ROOTFS, "etc/init.d/S20yi-hack")) or []):
        step("S20yi-hack", ln)

    out("")
    out("-- Process C: scripts S20 invokes, in order (full-boot path): apply_config, wifi_up,")
    out("              mount_cifs, apply_config, build_view, system.sh  (each a child: shared mounts) --")
    for name in ("apply_config.sh", "wifi_up.sh", "mount_cifs.sh", "apply_config.sh",
                 "build_view.sh", "system.sh"):
        out(f"  --- {name} ---")
        for ln in (_read_lines(os.path.join(SCR, name)) or [f"  <NOT FOUND {name}>\n"]):
            step(name.replace(".sh", ""), ln)

    out("")
    out(f"  FINAL: /tmp/sd {'IS' if '/tmp/sd' in mtab else 'is NOT'} mounted | boot-log fd -> {fd[0]}")
    out(f"  mount table at end: {dict(sorted(mtab.items()))}")

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
trace_boot_io()

out("")
out("=" * 78)
out(f" RESULT: {errors} error(s), {warns} warning(s)")
out(" Legend: ok=resolves now | .7z=expanded on first boot | DANGLING/FAIL=boot risk")
out("=" * 78)

with open(os.path.join(REPO, "simulated_boot.log"), "w") as f:
    f.write("\n".join(log_lines) + "\n")
print("\n".join(log_lines))
sys.exit(1 if errors else 0)
