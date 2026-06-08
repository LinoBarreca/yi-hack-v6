var APP = APP || {};

APP.mqtt_adv = (function ($) {

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
        loadingStatusElem = $('#loading-status');
        loadingStatusElem.text("Loading...");

        $.ajax({
            type: "GET",
            url: 'cgi-bin/get_configs.sh?conf=mqtt_advertise',
            dataType: "json",
            success: function (response) {
                loadingStatusElem.fadeOut(500);

                $.each(response, function (key, state) {
                    if (key == "HOMEASSISTANT_BOOT" || key == "HOMEASSISTANT_CRON" || key == "HOMEASSISTANT_ENABLE" || 
                        key == "INFO_GLOBAL_ENABLE" || key == "INFO_GLOBAL_BOOT" || key == "INFO_GLOBAL_CRON" || 
                        key == "LINK_ENABLE" || key == "LINK_BOOT" || key == "LINK_CRON" ||
                        key == "CAMERA_SETTING_ENABLE" || key == "CAMERA_SETTING_BOOT" || key == "CAMERA_SETTING_CRON" ||
                        key == "TELEMETRY_ENABLE" || key == "TELEMETRY_BOOT" || key == "TELEMETRY_CRON") {
                        $('input[type="checkbox"][data-key="' + key + '"]').prop('checked', state === 'yes');

                    } else {
                        $('input[type="text"][data-key="' + key + '"]').prop('value', state);
                    }
                });
            },
            error: function (response) {
                console.log('error', response);
            }
        });

        // HOMEASSISTANT_NAME / HOMEASSISTANT_IDENTIFIERS are per-camera identity
        // (config/identity.conf), not the centrally-managed mqtt_advertise.conf.
        $.ajax({
            type: "GET",
            url: 'cgi-bin/get_configs.sh?conf=identity',
            dataType: "json",
            success: function (response) {
                $.each(response, function (key, state) {
                    $('input[type="text"][data-key="' + key + '"]').prop('value', state);
                });
            },
            error: function (response) {
                console.log('error', response);
            }
        });

    }

    // Per-camera identity keys on this page -> config/identity.conf (not managed)
    var IDENTITY_KEYS = ["HOMEASSISTANT_NAME", "HOMEASSISTANT_IDENTIFIERS"];

    function saveConfigs() {
        var saveStatusElem;

        let configs = {};
        let configsIdentity = {};

        saveStatusElem = $('#save-status');
        saveStatusElem.text("Saving...");

        $('.configs-switch input[type="text"]').each(function () {
            configs[$(this).attr('data-key')] = $(this).prop('value');
        });

        $('.configs-switch input[type="password"]').each(function () {
            configs[$(this).attr('data-key')] = $(this).prop('value');
        });

        $('.configs-switch input[type="checkbox"]').each(function () {
            configs[$(this).attr('data-key')] = $(this).prop('checked') ? 'yes' : 'no';
        });

        // Split identity keys out to identity.conf
        IDENTITY_KEYS.forEach(function (k) {
            if (k in configs) { configsIdentity[k] = configs[k]; delete configs[k]; }
        });

        $.ajax({
            type: "POST",
            url: 'cgi-bin/set_configs.sh?conf=mqtt_advertise',
            data: JSON.stringify(configs),
            dataType: "json",
            success: function (response) {
                saveStatusElem.text("Saved");
            },
            error: function (response) {
                saveStatusElem.text("Error while saving");
                console.log('error', response);
            }
        });

        $.ajax({
            type: "POST",
            url: 'cgi-bin/set_configs.sh?conf=identity',
            data: JSON.stringify(configsIdentity),
            dataType: "json",
            success: function (response) {},
            error: function (response) {
                saveStatusElem.text("Error while saving");
                console.log('error', response);
            }
        });

    }

    return {
        init: init
    };

})(jQuery);
