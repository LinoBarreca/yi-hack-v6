var APP = APP || {};

APP.mqtt = (function ($) {

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
            url: 'cgi-bin/get_configs.sh?conf=mqtt',
            dataType: "json",
            success: function(response) {
                loadingStatusElem.fadeOut(500);

                $.each(response, function (key, state) {
                    if(key == "BROKER_PASSWORD")
                        $('input[type="password"][data-key="' + key +'"]').prop('value', state);
                    else if(key == "ENABLED")
                        $('input[type="checkbox"][data-key="' + key +'"]').prop('checked', state === 'yes');
                    else
                        $('input[type="text"][data-key="' + key +'"]').prop('value', state);
                });
            },
            error: function(response) {
                console.log('error', response);
            }
        });

        // MQTT_CLIENT_ID / MQTT_PREFIX are per-camera identity (config/identity.conf),
        // not in the centrally-managed mqtt.conf.
        $.ajax({
            type: "GET",
            url: 'cgi-bin/get_configs.sh?conf=identity',
            dataType: "json",
            success: function(response) {
                $.each(response, function (key, state) {
                    $('input[type="text"][data-key="' + key +'"]').prop('value', state);
                });
            },
            error: function(response) {
                console.log('error', response);
            }
        });
    }

    // Per-camera identity keys on this page -> config/identity.conf (not managed)
    var IDENTITY_KEYS = ["MQTT_CLIENT_ID", "MQTT_PREFIX"];

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

        // Master enable now lives in services/mqtt.conf (key ENABLED).
        configs["ENABLED"] = $("#enable-mqtt").prop('checked') ? 'yes' : 'no';

        // Split identity keys out to identity.conf
        IDENTITY_KEYS.forEach(function (k) {
            if (k in configs) { configsIdentity[k] = configs[k]; delete configs[k]; }
        });

        $.ajax({
            type: "POST",
            url: 'cgi-bin/set_configs.sh?conf=mqtt',
            data: JSON.stringify(configs),
            dataType: "json",
            success: function(response) {
                saveStatusElem.text("Saved");
            },
            error: function(response) {
                saveStatusElem.text("Error while saving");
                console.log('error', response);
            }
        });

        $.ajax({
            type: "POST",
            url: 'cgi-bin/set_configs.sh?conf=identity',
            data: JSON.stringify(configsIdentity),
            dataType: "json",
            success: function(response) {
            },
            error: function(response) {
                saveStatusElem.text("Error while saving");
                console.log('error', response);
            }
        });
    }

    return {
        init: init
    };

})(jQuery);
