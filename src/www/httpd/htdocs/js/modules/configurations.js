var APP = APP || {};

APP.configurations = (function ($) {

    // All fields on this page carry data-conf (which config file) and data-key
    // (the de-prefixed key in that file). We fetch/save one request per file.
    function fieldSelector() {
        return $('[data-conf][data-key]');
    }

    function confList() {
        var confs = {};
        fieldSelector().each(function () {
            confs[$(this).attr('data-conf')] = true;
        });
        return Object.keys(confs);
    }

    function setField($el, value) {
        if ($el.is(':checkbox')) {
            $el.prop('checked', value === 'yes');
        } else {
            $el.prop('value', value);
        }
    }

    function readField($el) {
        if ($el.is(':checkbox')) {
            return $el.prop('checked') ? 'yes' : 'no';
        }
        return $el.prop('value');
    }

    function init() {
        registerEventHandler();
        fetchConfigs();
    }

    function registerEventHandler() {
        $(document).on("click", '#button-save', function (e) {
            saveConfigs();
        });
    }

    function fetchConfigs() {
        var loadingStatusElem = $('#loading-status');
        loadingStatusElem.text("Loading...");

        var confs = confList();
        var pending = confs.length;
        if (pending === 0) {
            loadingStatusElem.fadeOut(500);
            return;
        }

        $.each(confs, function (i, conf) {
            $.ajax({
                type: "GET",
                url: 'cgi-bin/get_configs.sh?conf=' + conf,
                dataType: "json",
                success: function (response) {
                    $.each(response, function (key, state) {
                        if (key === 'NULL' || key === 'HOMEVER') return;
                        setField($('[data-conf="' + conf + '"][data-key="' + key + '"]'), state);
                    });
                },
                error: function (response) {
                    console.log('error', response);
                },
                complete: function () {
                    pending--;
                    if (pending === 0) loadingStatusElem.fadeOut(500);
                }
            });
        });
    }

    function saveConfigs() {
        var saveStatusElem = $('#save-status');
        saveStatusElem.text("Saving...");

        // Group field values by their config file.
        var byConf = {};
        fieldSelector().each(function () {
            var conf = $(this).attr('data-conf');
            var key = $(this).attr('data-key');
            byConf[conf] = byConf[conf] || {};
            byConf[conf][key] = readField($(this));
        });

        var confs = Object.keys(byConf);
        var pending = confs.length;
        var failed = false;

        $.each(confs, function (i, conf) {
            var configData = JSON.stringify(byConf[conf]);
            var escapedConfigData = configData.replace(/\\/g, "\\")
                                              .replace(/\\"/g, '\\"');
            $.ajax({
                type: "POST",
                url: 'cgi-bin/set_configs.sh?conf=' + conf,
                data: escapedConfigData,
                dataType: "json",
                error: function (response) {
                    failed = true;
                    console.log('error', response);
                },
                complete: function () {
                    pending--;
                    if (pending === 0) {
                        saveStatusElem.text(failed ? "Error while saving" : "Saved");
                    }
                }
            });
        });
    }

    function validateHostname(hostname) {
        return /^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$/.test(hostname);
    }

    return {
        init: init
    };

})(jQuery);
