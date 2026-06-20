var APP = APP || {};

APP.eventsdir = (function ($) {

    function init() {
        fetchConfigs();
        updateEventsDirPage();
        registerEventHandler();
    }

    function registerEventHandler() {
        $(document).on("click", '.button-primary', function (e) {
            buttonClick();
        });
    }

    function buttonClick() {
        if (event.target.id=="button-save") {
            saveConfigs();
        } else {
            deleteDir();
        }
    }

    function deleteDir() {
        $.ajax({
            type: "GET",
            url: 'cgi-bin/eventsdirdel.sh?dir='+event.target.id.substring(14),
            dataType: "json",
            success: function(response) {
                window.location.reload();
            },
            error: function(response) {
                console.log('error', response);
            }
        });
    }

    // Fields carry data-conf (config file) and data-key (de-prefixed key):
    // FREE_SPACE -> recording.conf, FTP_* -> services/ftp_upload.conf.
    function fieldSelector() {
        return $('[data-conf][data-key]');
    }

    function fetchConfigs() {
        loadingStatusElem = $('#loading-status');
        loadingStatusElem.text("Loading...");

        var confs = {};
        fieldSelector().each(function () { confs[$(this).attr('data-conf')] = true; });
        confs = Object.keys(confs);
        var pending = confs.length;
        if (pending === 0) { loadingStatusElem.fadeOut(500); return; }

        $.each(confs, function (i, conf) {
            $.ajax({
                type: "GET",
                url: 'cgi-bin/get_configs.sh?conf=' + conf,
                dataType: "json",
                success: function(response) {
                    $.each(response, function (key, state) {
                        if (key === 'NULL') return;
                        var $el = $('[data-conf="' + conf + '"][data-key="' + key + '"]');
                        if ($el.is(':checkbox')) $el.prop('checked', state === 'yes');
                        else $el.prop('value', state);
                    });
                },
                error: function(response) { console.log('error', response); },
                complete: function () { if (--pending === 0) loadingStatusElem.fadeOut(500); }
            });
        });
    }


   function saveConfigs() {
        var saveStatusElem = $('#save-status');
        saveStatusElem.text("Saving...");

        var byConf = {};
        fieldSelector().each(function () {
            var conf = $(this).attr('data-conf');
            var key = $(this).attr('data-key');
            byConf[conf] = byConf[conf] || {};
            byConf[conf][key] = $(this).is(':checkbox') ? ($(this).prop('checked') ? 'yes' : 'no') : $(this).prop('value');
        });

        var confs = Object.keys(byConf);
        var pending = confs.length;
        var failed = false;

        $.each(confs, function (i, conf) {
            $.ajax({
                type: "POST",
                url: 'cgi-bin/set_configs.sh?conf=' + conf,
                data: JSON.stringify(byConf[conf]),
                dataType: "json",
                error: function(response) { failed = true; console.log('error', response); },
                complete: function () {
                    if (--pending === 0) saveStatusElem.text(failed ? "Error while saving" : "Saved");
                }
            });
        });
    }

    function updateEventsDirPage() {
        html = "<table class=\"u-full-width padded-table\"><tbody>";
        $.ajax({
            type: "GET",
            url: 'cgi-bin/eventsdir.sh',
            dataType: "json",
            success: function(data) {
                html += "<tr><td><b>Date & time</b></td>";
                html += "<td><b>Directory name</b></td>";
                html += "<td><b>Delete directory</b></td></tr>";
                if (data.records.length == 0) {
                    html += "<tr><td>No events</td><td></td></tr>";
                } else {
                    for (var i = 0; i < data.records.length; i++) {
                        var record = data.records[i];
                        html += "<tr><td>" + record.datetime + "</td>";
                        html += "<td><a href=\"?page=eventsfile&dirname=" + record.dirname + "\">" + record.dirname + "</a></td>";
                        html += "<td><input class=\"button-primary\" type=\"button\" id=\"button-delete-" + record.dirname + "\" value=\"Delete\"/></td></tr>";
                    }
                }
                html += "</tbody></table>";
                document.getElementById("table-container").innerHTML = html;
            },
            error: function(response) {
                console.log('error', response);
            }
        });
    }

    return {
        init: init
    };

})(jQuery);
