/* yi-hack-v6 UI — dependency/ownership rules engine.
   One store answers "may the user edit this?" for every page:
     - build-time locked keys (config/locked.conf)         -> 🔒 model chip
     - cloud-owned time settings (cloud enabled)           -> ☁ cloud chip
     - centrally managed config files:
         from the network share (kind=cifs)                -> ⇩ share chip, read-only
         from the SD provisioning tree (kind=sd)           -> 💾 sd chip, editable but
           the save path warns that a reboot with the SD inserted reverts the values
   Pages bind :disabled / chips to these helpers instead of re-implementing
   the logic. Page-specific rules (recorder synthesis, ONVIF↔RTSP, lockout
   guard) live in their page components but consult this store first. */

'use strict';

document.addEventListener('alpine:init', () => {

    Alpine.store('rules', {
        locked: {},     // dotted path -> forced value, e.g. "services.rtsp.STREAM": "low"
        cifs: [],       // config files provisioned from the network share
        sd: [],         // config files provisioned from the SD card
        loaded: false,
        _prov: {},      // cache: file -> {KEY: value} provisioning copy

        async init() {
            try {
                const l = await api.getConf('locked');
                delete l.NULL;
                this.locked = l;
            } catch (e) { /* no locked.conf -> nothing locked */ }
            try {
                /* apply_config runs twice at boot (SD pass, then CIFS pass), so
                   both trees provision files in union - CIFS wins per-file */
                const m = await api.json('cgi-bin/conf_source.sh');
                this.cifs = m.cifs || [];
                this.sd = m.sd || [];
            } catch (e) { /* no share/SD -> nothing managed */ }
            this.loaded = true;
        },

        /* ----- build-time locks (dotted getter syntax) ----- */
        isLocked(path)    { return Object.prototype.hasOwnProperty.call(this.locked, path); },
        lockedValue(path) { return this.locked[path]; },

        /* ----- centrally managed files (per-file source, CIFS wins) ----- */
        fileKind(file) {
            if (this.cifs.includes(file)) return 'cifs';
            if (this.sd.includes(file))   return 'sd';
            return '';
        },
        isManaged(file)   { return this.fileKind(file) !== ''; },

        /* Provisioning copy of a managed file (for the SD save warning). */
        async provValues(file) {
            if (!this._prov[file]) {
                const r = await api.json('cgi-bin/conf_source.sh?file=' + encodeURIComponent(file));
                this._prov[file] = r.values || {};
            }
            return this._prov[file];
        },

        /* ----- cloud ownership of time settings -----
           Live value: follows the unsaved cloud toggle when a page passes it,
           else the running state from status.json. */
        cloudOn(pending)  {
            if (pending !== undefined) return pending === 'no';   // DISABLE_CLOUD value
            return (Alpine.store('ui').status.disable_cloud === 'no');
        },

        /* Combined per-field verdict used by inputs:
           dis = disabled, chip = '' | 'model' | 'cloud' | 'share' | 'sd'
           SD-provisioned fields stay editable: the warning happens at save time. */
        field(path, file, extra) {
            if (this.isLocked(path))          return { dis: true, chip: 'model' };
            if (file) {
                const k = this.fileKind(file);
                if (k === 'cifs')             return { dis: true,  chip: 'share' };
                if (k === 'sd')               return { dis: false, chip: 'sd' };
            }
            if (extra && extra.cloudTime && this.cloudOn(extra.disableCloud))
                                              return { dis: true, chip: 'cloud' };
            return { dis: false, chip: '' };
        }
    });
});
