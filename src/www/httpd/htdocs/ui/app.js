/* yi-hack-v6 UI — shell: theme, router, API helpers, page components.
   No build step: Alpine.js processes fragments injected into #page-host
   (Alpine 3 auto-initializes DOM added after start). Page logic lives here as
   Alpine.data components; fragments in ui/pages/*.html reference them. */

'use strict';

/* ---------- API helpers ----------
   Every request carries a 20s timeout: the camera CGIs are slow (a few seconds
   on this CPU) but must never leave the UI waiting forever. */
async function fetchTimeout(url, opts = {}) {
    const ctl = new AbortController();
    const t = setTimeout(() => ctl.abort(), 20000);
    try {
        return await fetch(url, { cache: 'no-store', signal: ctl.signal, ...opts });
    } finally { clearTimeout(t); }
}
const api = {
    async json(url) {
        const r = await fetchTimeout(url);
        if (!r.ok) throw new Error(url + ' -> HTTP ' + r.status);
        return r.json();
    },
    async text(url) {
        const r = await fetchTimeout(url);
        return r.text();
    },
    getConf(name)  { return api.json('cgi-bin/get_configs.sh?conf=' + name); },
    /* body = one "KEY=url-encoded-value" per line: trivially parsed by the CGI
       in pure shell (jq took ~12s per run on the camera - see set_configs.sh) */
    async setConf(name, data) {
        const body = Object.entries(data)
            .map(([k, v]) => k + '=' + encodeURIComponent(v == null ? '' : v))
            .join('\n') + '\n';
        const r = await fetchTimeout('cgi-bin/set_configs.sh?conf=' + name,
                                     { method: 'POST', body });
        const j = await r.json();
        sdProvisionWarn(name, data);   // fire-and-forget: never fails the save
        return j;
    },
    status() { return api.json('cgi-bin/status.json'); }
};

/* conf name -> config file path, same mapping as set_configs.sh */
const SERVICE_CONFS = ['snapshot', 'httpd', 'rtsp', 'onvif', 'telnetd', 'sshd', 'ftpd',
                       'ftp_upload', 'ntpd', 'proxychains', 'mqtt', 'mqtt_advertise'];
function confFile(name) {
    return SERVICE_CONFS.includes(name) ? 'services/' + name + '.conf' : name + '.conf';
}

/* SD-provisioned configs are editable, but apply_config copies the SD copy back
   over them at every boot. After a successful save, warn per differing key. */
async function sdProvisionWarn(name, data) {
    try {
        const rules = Alpine.store('rules');
        const file = confFile(name);
        if (!rules || rules.fileKind(file) !== 'sd') return;
        const prov = await rules.provValues(file);
        for (const [k, v] of Object.entries(data)) {
            if (!(k in prov)) continue;
            if (String(v == null ? '' : v) === prov[k]) continue;
            Alpine.store('ui').toast(
                'Saved but the setting ' + k + ' differs from the value provisioned ' +
                'through the SD card. Rebooting with the SD inserted will revert the ' +
                'value to "' + prov[k] + '".');
        }
    } catch (e) { /* warning only - never break the save */ }
}

/* Fetch a config and drop the JSON-closing filler key. */
async function conf(name) {
    const c = await api.getConf(name);
    delete c.NULL;
    return c;
}

/* ---------- page registry ----------
   Each page = ui/pages/<id>.html fragment + Alpine.data component <id>Page. */
const PAGES = [
    { id: 'status',   label: 'Status',          group: 'Camera' },
    { id: 'live',     label: 'Live view',       group: 'Camera' },
    { id: 'records',  label: 'Recordings',      group: 'Camera' },
    { id: 'camera',   label: 'Camera settings', group: 'Camera' },
    { id: 'nvr',      label: 'Recording (NVR)', group: 'Setup' },
    { id: 'network',  label: 'Network & shares',group: 'Setup' },
    { id: 'services', label: 'Services',        group: 'Setup' },
    { id: 'system',   label: 'System',          group: 'Setup' },
    { id: 'diag',     label: 'Diagnostics',     group: 'Setup' }
];

document.addEventListener('alpine:init', () => {

    /* ---------- shell store (init() runs automatically on registration) ---------- */
    Alpine.store('ui', {
        page: new URL(window.location.href).searchParams.get('page') || 'status',
        pages: PAGES,
        hostname: (typeof hostname !== 'undefined') ? hostname : 'yi-hack-v6',
        status: {},            // last status.json payload (topbar pills + pages)
        toasts: [],            // persistent notices (e.g. SD provisioning warnings)

        toast(text) { this.toasts.push(text); },
        dismissToast(i) { this.toasts.splice(i, 1); },

        get theme() { return document.documentElement.getAttribute('data-bs-theme'); },
        initTheme() {
            const saved = localStorage.getItem('yh-theme');
            const dark = saved ? saved === 'dark'
                               : window.matchMedia('(prefers-color-scheme: dark)').matches;
            document.documentElement.setAttribute('data-bs-theme', dark ? 'dark' : 'light');
        },
        toggleTheme() {
            const next = this.theme === 'dark' ? 'light' : 'dark';
            document.documentElement.setAttribute('data-bs-theme', next);
            localStorage.setItem('yh-theme', next);
        },

        async open(id, push = true) {
            const p = this.pages.find(x => x.id === id);
            if (!p) return;
            this.page = id;
            if (push) history.pushState({}, '', '?page=' + id);
            const host = document.getElementById('page-host');
            try {
                host.innerHTML = await api.text('ui/pages/' + id + '.html');
            } catch (e) {
                host.innerHTML = '<div class="yh-card">Failed to load page: ' + e + '</div>';
            }
            document.title = this.hostname + ' - ' + p.label;
        },

        /* Cloud pill: show the RUNNING state (the stock daemons only switch at
           reboot), and flag when the saved config differs - a pill that flips
           on save while the processes are still up would be lying. */
        cloudPill() {
            const s = this.status;
            if (!s.p2p_running) return null;
            const running = s.p2p_running === 'yes';
            const wanted  = s.disable_cloud === 'no';
            if (running === wanted) return { text: running ? 'Cloud on' : 'Cloud off',
                                             dot: running ? 'dot ok' : 'dot' };
            return { text: running ? 'Cloud on — turns off after reboot'
                                   : 'Cloud off — turns on after reboot',
                     dot: 'dot warn' };
        },

        /* Never stack polls: the camera CGIs take seconds, so an overlapping
           request would pile up. All callers share the in-flight promise. */
        refreshStatus() {
            if (!this._inflight) {
                this._inflight = api.status()
                    .then(s => { this.status = s; })
                    .catch(() => { /* keep last */ })
                    .finally(() => { this._inflight = null; });
            }
            return this._inflight;
        },

        init() {
            this.initTheme();
            window.addEventListener('popstate', () => {
                const id = new URL(window.location.href).searchParams.get('page') || 'status';
                this.open(id, false);
            });
            this.refreshStatus();
            setInterval(() => this.refreshStatus(), 30000);
            this.open(this.page, false);
        }
    });

    /* ================= Status ================= */
    Alpine.data('statusPage', () => ({
        s: {}, ready: false, err: '', links: {},
        async init() {
            /* share the store's fetch instead of issuing a second expensive request */
            const ui = Alpine.store('ui');
            try {
                await ui.refreshStatus();
                this.s = ui.status;
                if (!this.s.model_suffix) {
                    this.err = 'The camera did not answer — it may be busy. Reload the page to retry.';
                }
            } finally { this.ready = true; }
            try { this.links = await api.json('cgi-bin/links.sh'); } catch (e) { this.links = {}; }
        },
        linkRows() {
            const label = { high_res_stream: 'RTSP stream (high res)',
                            low_res_stream:  'RTSP stream (low res)',
                            audio_stream:    'RTSP audio',
                            high_res_snapshot: 'Snapshot (high res)',
                            low_res_snapshot:  'Snapshot (low res)' };
            return Object.entries(this.links)
                .filter(([k]) => label[k])
                .map(([k, v]) => ({ label: label[k], url: v, http: v.startsWith('http') }));
        },
        fmtUptime() {
            const t = parseFloat(this.s.uptime || 0);
            const d = Math.floor(t / 86400), h = Math.floor(t % 86400 / 3600),
                  m = Math.floor(t % 3600 / 60);
            return (d ? d + 'd ' : '') + h + 'h ' + m + 'm';
        },
        fmtMem() {
            const tot = parseInt(this.s.total_memory || 0), free = parseInt(this.s.free_memory || 0);
            if (!tot) return '—';
            return Math.round(free / 1024) + ' MB free of ' + Math.round(tot / 1024) + ' MB';
        },
        firmwareIn() {
            return { network: 'Network share', sd: 'SD card', rescue: 'Flash only (rescue)' }
                   [this.s.firmware_source] || this.s.firmware_source || '—';
        },
        svcChip(v) { return v === 'yes' ? 'chip state-ok' : 'chip state-off'; },
        svcText(v) { return v === 'yes' ? 'running' : 'off'; }
    }));

    /* ================= System ================= */
    Alpine.data('systemPage', () => ({
        sys: {}, ntpd: {}, out: {}, proxy: {}, upd: {},
        ready: false, savemsg: '', restoremsg: '', flashmsg: '', flashing: false,
        tzLoc: '', proxyServers: '', _proxyServers0: '',

        async init() {
            try {
                [this.sys, this.ntpd, this.out, this.proxy] = await Promise.all(
                    ['system', 'ntpd', 'output', 'proxychains'].map(conf));
            } finally { this.ready = true; }
            /* preselect the location matching the saved TZ string, if any */
            const cur = (this.sys.TIMEZONE || '').trim();
            const hit = this.tzZones.find(z => z[1] === cur);
            this.tzLoc = hit ? hit[0] : '';
            try {
                const p = await api.json('cgi-bin/proxy_servers.sh');
                this.proxyServers = this._proxyServers0 = (p.servers || '').split(';').join('\n');
            } catch (e) { /* editor stays empty */ }
            try { this.upd = await api.json('cgi-bin/update_backend.sh'); } catch (e) { this.upd = {}; }
        },

        get cloudEnabled()  { return this.sys.DISABLE_CLOUD === 'no'; },
        set cloudEnabled(v) { this.sys.DISABLE_CLOUD = v ? 'no' : 'yes'; },

        /* ----- timezone picker (location -> POSIX TZ string incl. DST rules) ----- */
        tzZones: (typeof TZ_ZONES !== 'undefined') ? TZ_ZONES : [],
        tzPick() {
            const hit = this.tzZones.find(z => z[0] === this.tzLoc);
            if (hit) this.sys.TIMEZONE = hit[1];
        },

        /* time settings follow the (unsaved) cloud toggle: while the cloud is
           enabled, time & timezone are cloud-managed */
        timeField(path, file) {
            return Alpine.store('rules').field(path, file,
                { cloudTime: true, disableCloud: this.sys.DISABLE_CLOUD });
        },
        f(path, file) { return Alpine.store('rules').field(path, file); },

        async save() {
            this.savemsg = 'Saving…';
            try {
                const sysPayload = {
                    DISABLE_CLOUD: this.sys.DISABLE_CLOUD,
                    CHECK_UPDATES: this.sys.CHECK_UPDATES || 'no',
                    CRONTAB: this.sys.CRONTAB || ''
                };
                if (!this.timeField('system.TIMEZONE', 'system.conf').dis)
                    sysPayload.TIMEZONE = this.sys.TIMEZONE || '';
                await api.setConf('system', sysPayload);
                if (!this.timeField('services.ntpd.ENABLED', 'services/ntpd.conf').dis)
                    await api.setConf('ntpd', { ENABLED: this.ntpd.ENABLED || 'no',
                                                SERVER: this.ntpd.SERVER || '' });
                await api.setConf('output', { SWAP_FILE: this.out.SWAP_FILE || 'NO' });
                const proxyPayload = { ENABLED: this.proxy.ENABLED || 'no' };
                if (this.proxyServers !== this._proxyServers0) {
                    /* only when edited: PROXYCHAINS_SERVERS rewrites the conf file */
                    proxyPayload.PROXYCHAINS_SERVERS = this.proxyServers
                        .split('\n').map(s => s.trim()).filter(Boolean).join(';');
                    this._proxyServers0 = this.proxyServers;
                }
                await api.setConf('proxychains', proxyPayload);
                this.savemsg = 'Saved — most changes apply at the next reboot.';
                Alpine.store('ui').refreshStatus();
            } catch (e) { this.savemsg = 'Error while saving: ' + e; }
        },

        async reboot() {
            if (!confirm('Reboot the camera now?')) return;
            this.savemsg = 'Rebooting — the camera will be back in ~1 minute.';
            await api.json('cgi-bin/reboot.sh').catch(() => {});
        },
        async reset() {
            if (!confirm('Reset all service settings to their defaults?\n' +
                          'Network, identity, PTZ presets and model-locked settings are preserved.')) return;
            await api.json('cgi-bin/reset.sh').catch(() => {});
            this.savemsg = 'Settings reset to defaults — reboot to apply everywhere.';
            this.init();
        },

        /* settings backup restore: POST the tar.bz2 to load.sh (multipart) */
        async restore() {
            const f = this.$refs.restorefile.files[0];
            if (!f) { this.restoremsg = 'Choose a backup file first.'; return; }
            if (!confirm('Restore the settings from this backup? The camera should be rebooted afterwards.')) return;
            this.restoremsg = 'Restoring…';
            const fd = new FormData();
            fd.append('files[]', f, f.name);
            try {
                const r = await fetch('cgi-bin/load.sh', { method: 'POST', body: fd });
                this.restoremsg = (await r.text()).trim();
            } catch (e) { this.restoremsg = 'Restore failed: ' + e; }
        },

        /* firmware images -> SD; the bootloader flashes them at the next boot */
        async flash() {
            const home = this.$refs.fwhome.files[0], rootfs = this.$refs.fwrootfs.files[0];
            if (!home || !rootfs) { this.flashmsg = 'Select BOTH the home and rootfs images.'; return; }
            if (!home.name.startsWith('home') || !rootfs.name.startsWith('rootfs')) {
                this.flashmsg = 'Wrong file names: expected home_* and rootfs_* images.'; return;
            }
            if (!confirm('Upload the firmware images to the SD card?\n' +
                         'They are flashed by the bootloader at the next reboot.')) return;
            this.flashing = true; this.flashmsg = '';
            try {
                for (const f of [home, rootfs]) {
                    const fd = new FormData();
                    fd.append('file', f, f.name);
                    const r = await fetch('cgi-bin/upload.sh?file=' + encodeURIComponent(f.name),
                                          { method: 'POST', body: fd });
                    if (!r.ok) throw new Error(f.name + ' -> HTTP ' + r.status);
                }
                this.flashmsg = 'Uploaded. Reboot the camera and wait a couple of minutes.';
            } catch (e) { this.flashmsg = 'Upload failed: ' + e; }
            this.flashing = false;
        }
    }));

    /* ================= Recording (NVR) ================= */
    Alpine.data('nvrPage', () => ({
        out: {}, rec: {}, sys: {}, rtsp: {}, cam: {}, ftp: {}, cifs: {},
        status: {}, mode: 'off', dest: 'SD',
        ready: false, savemsg: '',

        async init() {
            try {
                [this.out, this.rec, this.sys, this.rtsp, this.cam, this.ftp, this.cifs] =
                    await Promise.all(['output', 'recording', 'system', 'rtsp', 'camera',
                                       'ftp_upload', 'cifs'].map(conf));
            } catch (e) { this.ready = true; return; }
            this.status = Alpine.store('ui').status;
            /* derive the single recorder choice from the underlying flags:
               output.RECORD != NO -> native; else the stock recorder runs whenever
               the cloud is on, or REC_WITHOUT_CLOUD keeps it on with cloud off. */
            if (this.out.RECORD && this.out.RECORD !== 'NO') {
                this.mode = 'native';
                this.dest = this.out.RECORD;
            } else if (this.sys.DISABLE_CLOUD === 'no' || this.sys.REC_WITHOUT_CLOUD === 'yes') {
                this.mode = 'stock';
            } else {
                this.mode = 'off';
            }
            this.ready = true;
        },

        /* with the cloud on, mp4record always runs -> "off" is not available */
        get offBlocked()   { return this.sys.DISABLE_CLOUD === 'no'; },
        get stockBlocked() { return this.status.sd_mounted !== 'yes'; },
        get rwConfigured() { return !!(this.cifs.RW_HOST || this.cifs.RW_SHARE); },

        async save() {
            this.savemsg = 'Saving…';
            try {
                if (this.mode === 'native') {
                    if (this.rtsp.ENABLED !== 'yes') {
                        await api.setConf('rtsp', { ENABLED: 'yes' });
                        this.rtsp.ENABLED = 'yes';
                    }
                    await api.setConf('output', { RECORD: this.dest });
                    await api.setConf('recording', {
                        SEGMENT_TIME: this.rec.SEGMENT_TIME || '60',
                        FREE_SPACE: this.rec.FREE_SPACE || '10'
                    });
                    await api.setConf('system', { REC_WITHOUT_CLOUD: 'no' });
                } else if (this.mode === 'stock') {
                    await api.setConf('output', { RECORD: 'NO' });
                    await api.setConf('system', {
                        REC_WITHOUT_CLOUD: this.sys.DISABLE_CLOUD === 'yes' ? 'yes' : 'no'
                    });
                    /* stock record mode is a live camera setting (same as the Yi app) */
                    await api.text('cgi-bin/camera_settings.sh?save_video_on_motion=' +
                                   (this.cam.SAVE_VIDEO_ON_MOTION === 'no' ? 'no' : 'yes'));
                } else {
                    await api.setConf('output', { RECORD: 'NO' });
                    await api.setConf('system', { REC_WITHOUT_CLOUD: 'no' });
                }
                await api.setConf('ftp_upload', {
                    ENABLED: (this.mode !== 'off' && this.ftp.ENABLED === 'yes') ? 'yes' : 'no',
                    HOST: this.ftp.HOST || '', DIR: this.ftp.DIR || '',
                    DIR_TREE: this.ftp.DIR_TREE || 'no',
                    USERNAME: this.ftp.USERNAME || '', PASSWORD: this.ftp.PASSWORD || '',
                    FILE_DELETE_AFTER_UPLOAD: this.ftp.FILE_DELETE_AFTER_UPLOAD || 'no'
                });
                this.savemsg = 'Saved — the recorder switches at the next reboot.';
                Alpine.store('ui').refreshStatus();
            } catch (e) { this.savemsg = 'Error while saving: ' + e; }
        }
    }));

    /* ================= Recordings browser ================= */
    Alpine.data('recordsPage', () => ({
        dirs: [], files: [], sel: '', ready: false,
        player: '', playerName: '', playerError: false,

        async init() {
            try {
                const r = await api.json('cgi-bin/eventsdir.sh');
                this.dirs = (r.records || []).filter(d => d.dirname);
            } catch (e) { this.dirs = []; }
            this.ready = true;
        },
        fmtDir(d)  { return d.slice(0, 4) + '-' + d.slice(5, 7) + '-' + d.slice(8, 10) +
                            ' ' + d.slice(11, 13) + ':00'; },
        fmtFile(f) { return this.sel.slice(11, 13) + ':' + f.slice(0, 2) + ':' + f.slice(3, 5); },
        async openDir(d) {
            this.sel = d;
            try {
                const r = await api.json('cgi-bin/eventsfile.sh?dirname=' + d);
                this.files = (r.records || []).filter(f => f.filename);
            } catch (e) { this.files = []; }
        },
        play(d, f) {
            this.playerError = false;
            this.player = 'cgi-bin/playrecord.sh?dir=' + d + '&file=' + f;
            this.playerName = this.fmtDir(d) + ' → ' + this.fmtFile(f);
            window.scrollTo({ top: 0 });
        },
        async delDir(d) {
            if (!confirm('Delete ALL clips of ' + this.fmtDir(d) + '?')) return;
            await api.json('cgi-bin/eventsdirdel.sh?dir=' + d).catch(() => {});
            this.sel = ''; this.files = [];
            this.init();
        },
        async delFile(d, f) {
            if (!confirm('Delete this clip?')) return;
            await api.json('cgi-bin/eventsfiledel.sh?file=' + d + '/' + f).catch(() => {});
            this.openDir(d);
        }
    }));

    /* ================= Network & shares ================= */
    Alpine.data('networkPage', () => ({
        sys: {}, cifs: {},
        wifi: { ssid: '', psk: '', psk2: '' },
        ssids: [], scanning: false, ready: false,
        hostmsg: '', wifimsg: '', cifsmsg: '',
        testmsg: { ro: '', rw: '' },

        async init() {
            try {
                [this.sys, this.cifs] = await Promise.all(['system', 'cifs'].map(conf));
            } finally { this.ready = true; }
        },
        /* cifs.conf on the share = the whole card is centrally managed */
        get managed() { return Alpine.store('rules').isManaged('cifs.conf'); },

        async saveHost() {
            this.hostmsg = 'Saving…';
            try {
                await api.setConf('system', { HOSTNAME: this.sys.HOSTNAME || '' });
                this.hostmsg = 'Saved.';
                Alpine.store('ui').refreshStatus();
            } catch (e) { this.hostmsg = 'Error while saving: ' + e; }
        },

        async scan() {
            this.scanning = true;
            try {
                const r = await api.json('cgi-bin/wifi.sh?action=scan');
                this.ssids = (r.wifi || []).filter(Boolean);
            } catch (e) { /* scan can fail while associated - keep list */ }
            this.scanning = false;
        },
        async saveWifi() {
            if (!this.wifi.ssid) { this.wifimsg = 'Enter the network name first.'; return; }
            if (this.wifi.psk !== this.wifi.psk2) { this.wifimsg = 'The two passwords do not match.'; return; }
            if (!confirm('Save WiFi credentials and reconnect?\nIf they are wrong the camera may drop off the network.')) return;
            this.wifimsg = 'Saving…';
            try {
                const body = ['WIFI_ESSID=' + encodeURIComponent(this.wifi.ssid),
                              'WIFI_PASSWORD=' + encodeURIComponent(this.wifi.psk),
                              'WIFI_PASSWORD2=' + encodeURIComponent(this.wifi.psk2)].join('\n') + '\n';
                const r = await fetchTimeout('cgi-bin/wifi.sh?action=save',
                                             { method: 'POST', body }).then(x => x.json());
                this.wifimsg = r.error === 'false' ? 'Saved — the camera is reconnecting.' : 'Save failed.';
            } catch (e) { this.wifimsg = 'Error: ' + e; }
        },

        async saveCifs() {
            this.cifsmsg = 'Saving…';
            try {
                await api.setConf('cifs', {
                    ENABLED: this.cifs.ENABLED || 'no',
                    HOST: this.cifs.HOST || '', SHARE: this.cifs.SHARE || '',
                    USER: this.cifs.USER || '', PASS: this.cifs.PASS || '',
                    SEC: this.cifs.SEC || '', VERS: this.cifs.VERS || '',
                    RETRY: this.cifs.RETRY || '', RETRY_DELAY: this.cifs.RETRY_DELAY || '',
                    RW_HOST: this.cifs.RW_HOST || '', RW_SHARE: this.cifs.RW_SHARE || '',
                    RW_USER: this.cifs.RW_USER || '', RW_PASS: this.cifs.RW_PASS || ''
                });
                this.cifsmsg = 'Saved — shares are (re)mounted at the next reboot.';
            } catch (e) { this.cifsmsg = 'Error while saving: ' + e; }
        },
        async test(kind) {
            this.testmsg[kind] = 'Testing…';
            try {
                const r = await api.json('cgi-bin/cifstest.sh?share=' + kind);
                this.testmsg[kind] = (r.ok === 'yes' ? '✓ ' : '✗ ') + r.msg;
            } catch (e) { this.testmsg[kind] = '✗ test failed: ' + e; }
        }
    }));

    /* ================= Camera settings ================= */
    Alpine.data('cameraPage', () => ({
        c: {}, dirty: [], presets: [], newPreset: '',
        ready: false, savemsg: '',
        hwToggles: [
            { key: 'LED',    label: 'Status LED' },
            { key: 'IR',     label: 'IR night vision' },
            { key: 'MIC',    label: 'Microphone' },
            { key: 'ROTATE', label: 'Rotate image 180°' }
        ],
        aiToggles: [
            { key: 'AI_HUMAN_DETECTION',   label: 'People' },
            { key: 'AI_VEHICLE_DETECTION', label: 'Vehicles' },
            { key: 'AI_ANIMAL_DETECTION',  label: 'Animals' },
            { key: 'FACE_DETECTION',       label: 'Faces' }
        ],

        async init() {
            try {
                this.c = await conf('camera');
                if (this.isPtz) await this.loadPresets();
            } finally { this.ready = true; }
        },
        get isPtz() { return Alpine.store('ui').status.ptz === 'yes'; },
        lk(key) { return Alpine.store('rules').isLocked('camera.' + key); },

        mark(key) { if (!this.dirty.includes(key)) this.dirty.push(key); },
        set(key, checked) { this.c[key] = checked ? 'yes' : 'no'; this.mark(key); },

        /* apply only what changed: one request per setting (the CGI sends the
           IPC command; mqttv4 persists the echo into camera.conf) */
        async save() {
            this.savemsg = 'Applying…';
            try {
                for (const key of this.dirty) {
                    await api.text('cgi-bin/camera_settings.sh?' +
                                   key.toLowerCase() + '=' + encodeURIComponent(this.c[key]));
                }
                this.savemsg = 'Applied (' + this.dirty.length + ' change' +
                               (this.dirty.length > 1 ? 's' : '') + ').';
                this.dirty = [];
            } catch (e) { this.savemsg = 'Error while applying: ' + e; }
        },

        async loadPresets() {
            try {
                const p = await conf('ptz_presets');
                this.presets = Object.entries(p).map(([num, name]) => ({ num, name }));
            } catch (e) { this.presets = []; }
        },
        async goPreset(n)  { await api.json('cgi-bin/preset.sh?action=go_preset&num=' + n).catch(() => {}); },
        async delPreset(n) {
            if (!confirm('Delete this preset?')) return;
            await api.json('cgi-bin/preset.sh?action=del_preset&num=' + n).catch(() => {});
            this.loadPresets();
        },
        async addPreset() {
            if (!this.newPreset) return;
            await api.json('cgi-bin/preset.sh?action=add_preset&name=' +
                           encodeURIComponent(this.newPreset)).catch(() => {});
            this.newPreset = '';
            this.loadPresets();
        }
    }));

    /* ================= Live view ================= */
    Alpine.data('livePage', () => ({
        res: 'high', every: 3, err: false,
        src: '', timer: null, snapshotOff: false,

        async init() {
            try { this.snapshotOff = (await conf('snapshot')).ENABLED === 'no'; }
            catch (e) { this.snapshotOff = false; }
            this.refresh();
            this.setEvery(this.every);
        },
        destroy() { if (this.timer) clearInterval(this.timer); },
        get isPtz() { return Alpine.store('ui').status.ptz === 'yes'; },

        refresh() {
            if (this.snapshotOff) return;
            this.src = 'cgi-bin/snapshot.sh?res=' + this.res + '&t=' + Date.now();
        },
        setEvery(i) {
            this.every = i;
            if (this.timer) clearInterval(this.timer);
            this.timer = null;
            if (i > 0) this.timer = setInterval(() => this.refresh(), i * 1000);
            this.refresh();
        },
        async move(dir) {
            await api.json('cgi-bin/ptz.sh?dir=' + dir + '&time=0.3').catch(() => {});
            setTimeout(() => this.refresh(), 600);
        }
    }));

    /* ================= Services ================= */
    Alpine.data('servicesPage', () => ({
        rtsp: {}, onvif: {}, snap: {}, mq: {}, adv: {}, ident: {},
        httpd: {}, sshd: {}, telnetd: {}, ftpd: {},
        ready: false, msg: { stream: '', mqtt: '', access: '' },

        mqttAdvKeys: ['TOPIC_BIRTH_WILL', 'BIRTH_MSG', 'WILL_MSG',
            'TOPIC_MOTION', 'MOTION_START_MSG', 'MOTION_STOP_MSG',
            'TOPIC_MOTION_IMAGE', 'MOTION_IMAGE_DELAY', 'TOPIC_MOTION_FILES',
            'TOPIC_SOUND_DETECTION', 'SOUND_DETECTION_MSG',
            'AI_HUMAN_DETECTION_MSG', 'AI_VEHICLE_DETECTION_MSG',
            'AI_ANIMAL_DETECTION_MSG', 'BABY_CRYING_MSG',
            'KEEPALIVE', 'QOS', 'RETAIN_BIRTH_WILL', 'RETAIN_MOTION',
            'RETAIN_MOTION_IMAGE', 'RETAIN_MOTION_FILES', 'RETAIN_SOUND_DETECTION'],
        advGroups: [
            { key: 'HOMEASSISTANT',  label: 'Home Assistant discovery (entities)' },
            { key: 'CAMERA_SETTING', label: 'Camera settings state' },
            { key: 'TELEMETRY',      label: 'Telemetry (uptime, WiFi, …)' },
            { key: 'INFO_GLOBAL',    label: 'Camera info' },
            { key: 'LINK',           label: 'Quick links (RTSP/snapshot URLs)' }
        ],

        async init() {
            try {
                [this.rtsp, this.onvif, this.snap, this.mq, this.adv, this.ident,
                 this.httpd, this.sshd, this.telnetd, this.ftpd] =
                    await Promise.all(['rtsp', 'onvif', 'snapshot', 'mqtt', 'mqtt_advertise',
                                       'identity', 'httpd', 'sshd', 'telnetd', 'ftpd'].map(conf));
            } finally { this.ready = true; }
        },

        lk(path)  { return Alpine.store('rules').isLocked(path); },
        dis(path) { return Alpine.store('rules').isLocked(path); },
        mg(file)  { return Alpine.store('rules').isManaged(file); },

        profileMismatch() {
            if (this.onvif.ENABLED !== 'yes' || this.rtsp.ENABLED !== 'yes') return false;
            const p = this.onvif.PROFILE, s = this.rtsp.STREAM;
            return p === 'both' ? s !== 'both' : (s !== p && s !== 'both');
        },

        async saveStreaming() {
            /* ONVIF depends on RTSP; the profile must match a published stream */
            if (this.onvif.ENABLED === 'yes') {
                if (this.rtsp.ENABLED !== 'yes') {
                    if (!confirm('ONVIF advertises the RTSP stream, which is currently off.\n' +
                                 'Enable the RTSP stream too?')) return;
                    this.rtsp.ENABLED = 'yes';
                }
                if (this.profileMismatch()) {
                    const target = this.onvif.PROFILE === 'both' ? 'both' : this.onvif.PROFILE;
                    if (!confirm('The ONVIF profile "' + this.onvif.PROFILE + '" needs the RTSP ' +
                                 'stream set to "' + target + '".\nChange the RTSP stream too?')) return;
                    this.rtsp.STREAM = target;
                }
            }
            this.msg.stream = 'Saving…';
            try {
                await api.setConf('rtsp', {
                    ENABLED: this.rtsp.ENABLED || 'no', STREAM: this.rtsp.STREAM || 'high',
                    AUDIO: this.rtsp.AUDIO || 'no', PORT: this.rtsp.PORT || '554',
                    TIME_OSD: this.rtsp.TIME_OSD || 'no',
                    USER: this.rtsp.USER || '', PASSWORD: this.rtsp.PASSWORD || ''
                });
                await api.setConf('onvif', {
                    ENABLED: this.onvif.ENABLED || 'no', WSDD: this.onvif.WSDD || 'no',
                    PROFILE: this.onvif.PROFILE || 'high',
                    SNAPSHOT: this.onvif.SNAPSHOT || 'same'
                });
                await api.setConf('snapshot', {
                    ENABLED: this.snap.ENABLED || 'yes',
                    RESOLUTION: this.snap.RESOLUTION || 'high',
                    WATERMARK: this.snap.WATERMARK || 'no'
                });
                this.msg.stream = 'Saved — streaming services restart at the next reboot.';
            } catch (e) { this.msg.stream = 'Error while saving: ' + e; }
        },

        async saveMqtt() {
            this.msg.mqtt = 'Saving…';
            try {
                const payload = {
                    ENABLED: this.mq.ENABLED || 'no',
                    CONFIG_ENABLED: this.mq.CONFIG_ENABLED || 'yes',
                    BROKER_IP: this.mq.BROKER_IP || '', BROKER_PORT: this.mq.BROKER_PORT || '1883',
                    BROKER_USER: this.mq.BROKER_USER || '', BROKER_PASSWORD: this.mq.BROKER_PASSWORD || ''
                };
                this.mqttAdvKeys.forEach(k => { if (this.mq[k] !== undefined) payload[k] = this.mq[k]; });
                await api.setConf('mqtt', payload);
                const advPayload = {};
                this.advGroups.forEach(g => ['_ENABLE', '_BOOT', '_CRON', '_CRONTAB'].forEach(sfx => {
                    const k = g.key + sfx;
                    if (this.adv[k] !== undefined) advPayload[k] = this.adv[k];
                }));
                await api.setConf('mqtt_advertise', advPayload);
                await api.setConf('identity', {
                    MQTT_CLIENT_ID: this.ident.MQTT_CLIENT_ID || '',
                    MQTT_PREFIX: this.ident.MQTT_PREFIX || '',
                    HOMEASSISTANT_NAME: this.ident.HOMEASSISTANT_NAME || '',
                    HOMEASSISTANT_IDENTIFIERS: this.ident.HOMEASSISTANT_IDENTIFIERS || ''
                });
                this.msg.mqtt = 'Saved — MQTT reconnects at the next reboot.';
            } catch (e) { this.msg.mqtt = 'Error while saving: ' + e; }
        },

        async saveAccess() {
            /* self-lockout guard */
            if (this.httpd.ENABLED === 'no' && this.sshd.ENABLED === 'no' &&
                this.telnetd.ENABLED === 'no') {
                alert('Refused: web, SSH and telnet cannot ALL be off — you would lose every ' +
                      'way to manage the camera. Leave at least one enabled.');
                return;
            }
            if (this.httpd.ENABLED === 'no' &&
                !confirm('You are turning off THIS web interface.\nAfter the next reboot the ' +
                         'camera is manageable only via SSH/telnet. Continue?')) return;
            this.msg.access = 'Saving…';
            try {
                await api.setConf('httpd', {
                    ENABLED: this.httpd.ENABLED || 'yes', PORT: this.httpd.PORT || '80',
                    USER: this.httpd.USER || '', PASSWORD: this.httpd.PASSWORD || ''
                });
                await api.setConf('sshd', {
                    ENABLED: this.sshd.ENABLED || 'yes', PASSWORD: this.sshd.PASSWORD || ''
                });
                await api.setConf('telnetd', { ENABLED: this.telnetd.ENABLED || 'no' });
                await api.setConf('ftpd', { ENABLED: this.ftpd.ENABLED || 'no' });
                this.msg.access = 'Saved — access services change at the next reboot.';
            } catch (e) { this.msg.access = 'Error while saving: ' + e; }
        }
    }));

    /* ================= Diagnostics ================= */
    Alpine.data('diagPage', () => ({
        logs: [], sel: '', content: '', ready: false,
        sys: {}, out: {}, savemsg: '',
        testmsg: { ro: '', rw: '' },
        labels: {
            boot: 'Boot log', dmesg: 'Kernel (dmesg)', ps: 'Processes',
            meminfo: 'Memory', mounts: 'Mounts', df: 'Disk space',
            netstat: 'Open ports', wifi: 'WiFi state',
            wd_rtsp: 'RTSP watchdog', onvif: 'ONVIF server',
            onvif_notify: 'ONVIF notify', wsd: 'WS-Discovery',
            stock_log: 'Stock: main', stock_alarm: 'Stock: alarm',
            stock_p2p: 'Stock: P2P', stock_oss: 'Stock: cloud upload'
        },

        async init() {
            try {
                const l = await api.json('cgi-bin/diag_log.sh?name=list');
                this.logs = l.logs || [];
                [this.sys, this.out] = await Promise.all(['system', 'output'].map(conf));
            } catch (e) { /* leave what loaded */ }
            this.ready = true;
        },
        label(id) { return this.labels[id] || id; },
        async view(id) {
            this.sel = id;
            this.content = 'Loading…';
            this.content = await api.text('cgi-bin/diag_log.sh?name=' + id);
        },
        dl(id) { return 'cgi-bin/diag_log.sh?name=' + id + '&download=1'; },

        async saveLogCfg() {
            this.savemsg = 'Saving…';
            try {
                await api.setConf('system', { DEBUG_LOG: this.sys.DEBUG_LOG || 'no' });
                await api.setConf('output', { LOG: this.out.LOG || 'RAM' });
                this.savemsg = 'Saved — log destinations apply at the next reboot.';
            } catch (e) { this.savemsg = 'Error while saving: ' + e; }
        },
        async cifstest(kind) {
            this.testmsg[kind] = 'Testing…';
            try {
                const r = await api.json('cgi-bin/cifstest.sh?share=' + kind);
                this.testmsg[kind] = (r.ok === 'yes' ? '✓ ' : '✗ ') + r.msg;
            } catch (e) { this.testmsg[kind] = '✗ test failed: ' + e; }
        }
    }));
});
