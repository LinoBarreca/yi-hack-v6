#include "validate.h"

char *config_params[][PARAM_OPTIONS] = {
    /* system - generic settings (section = config/system.conf) */
    { "system", "DISABLE_CLOUD", "bool", "", "", "" , "", "", "" },
    { "system", "REC_WITHOUT_CLOUD", "bool", "", "", "" , "", "", "" },
    { "system", "TIMEZONE", "string", "", "", "" , "", "", "" },
    { "system", "CRONTAB", "string", "", "", "" , "", "", "" },
    { "system", "DEBUG_LOG", "bool", "", "", "" , "", "", "" },

    /* recording - retention (section = config/recording.conf) */
    { "recording", "FREE_SPACE", "int", "0", "100", "" , "", "", "" },
    { "recording", "SEGMENT_TIME", "int", "1", "3600", "" , "", "", "" },
    /* Which stream to record; high needs swap (see record.sh). */
    { "recording", "STREAM", "enum", "high", "low", "" , "", "", "" },

    /* snapshot (section = config/services/snapshot.conf) */
    { "services/snapshot", "ENABLED", "bool", "", "", "" , "", "", "" },
    { "services/snapshot", "RESOLUTION", "enum", "high", "low", "" , "", "", "" },
    { "services/snapshot", "WATERMARK", "bool", "", "", "" , "", "", "" },

    /* httpd (section = config/services/httpd.conf) */
    { "services/httpd", "ENABLED", "bool", "", "", "" , "", "", "" },
    { "services/httpd", "PORT", "int", "1", "65535", "" , "", "", "" },
    { "services/httpd", "USER", "string", "", "", "" , "", "", "" },
    { "services/httpd", "PASSWORD", "string", "", "", "" , "", "", "" },

    /* rtsp - credentials shared with onvif (section = config/services/rtsp.conf) */
    { "services/rtsp", "ENABLED", "bool", "", "", "" , "", "", "" },
    { "services/rtsp", "STREAM", "enum", "high", "low", "both" , "", "", "" },
    { "services/rtsp", "AUDIO", "enum", "no", "aac", "g711" , "", "", "" },
    { "services/rtsp", "AUDIO_QUALITY", "enum", "low", "high", "" , "", "", "" },
    /* Upper bound is the VQE ANR intensity range the hardware accepts ([0,25],
     * hi_comm_aio.h AUDIO_ANR_CONFIG_S) - campipe clamps to the same. */
    { "services/rtsp", "AUDIO_NR_LEVEL", "int", "0", "25", "" , "", "", "" },
    { "services/rtsp", "PORT", "int", "1", "65535", "" , "", "", "" },
    { "services/rtsp", "TIME_OSD", "bool", "", "", "" , "", "", "" },
    { "services/rtsp", "USER", "string", "", "", "" , "", "", "" },
    { "services/rtsp", "PASSWORD", "string", "", "", "" , "", "", "" },

    /* onvif (section = config/services/onvif.conf) */
    { "services/onvif", "ENABLED", "bool", "", "", "" , "", "", "" },
    { "services/onvif", "WSDD", "bool", "", "", "" , "", "", "" },
    { "services/onvif", "PROFILE", "enum", "high", "low", "both" , "", "", "" },
    { "services/onvif", "NETIF", "string", "", "", "" , "", "", "" },

    /* telnetd (section = config/services/telnetd.conf) */
    { "services/telnetd", "ENABLED", "bool", "", "", "" , "", "", "" },

    /* sshd (section = config/services/sshd.conf) */
    { "services/sshd", "ENABLED", "bool", "", "", "" , "", "", "" },
    { "services/sshd", "PASSWORD", "string", "", "", "" , "", "", "" },

    /* ftpd - server, tri-state (section = config/services/ftpd.conf) */
    { "services/ftpd", "ENABLED", "enum", "no", "busybox", "pureftpd" , "", "", "" },

    /* ftp_upload - client (section = config/services/ftp_upload.conf) */
    { "services/ftp_upload", "ENABLED", "bool", "", "", "" , "", "", "" },
    { "services/ftp_upload", "HOST", "string", "", "", "" , "", "", "" },
    { "services/ftp_upload", "DIR", "string", "", "", "" , "", "", "" },
    { "services/ftp_upload", "DIR_TREE", "bool", "", "", "" , "", "", "" },
    { "services/ftp_upload", "USERNAME", "string", "", "", "" , "", "", "" },
    { "services/ftp_upload", "PASSWORD", "string", "", "", "" , "", "", "" },
    { "services/ftp_upload", "FILE_DELETE_AFTER_UPLOAD", "bool", "", "", "" , "", "", "" },

    /* ntpd (section = config/services/ntpd.conf) */
    { "services/ntpd", "ENABLED", "bool", "", "", "" , "", "", "" },
    { "services/ntpd", "SERVER", "string", "", "", "" , "", "", "" },

    /* proxychains (section = config/services/proxychains.conf) */
    { "services/proxychains", "ENABLED", "bool", "", "", "" , "", "", "" },

    /* mqtt - master enable (section = config/services/mqtt.conf) */
    { "services/mqtt", "ENABLED", "bool", "", "", "" , "", "", "" },
    { "services/mqtt", "CONFIG_ENABLED", "bool", "", "", "" , "", "", "" },

    { "camera", "SWITCH_ON", "bool", "", "", "" , "", "", "ipc_cmd -t %s" },
    { "camera", "SAVE_VIDEO_ON_MOTION", "bool", "", "", "" , "", "", "ipc_cmd -v %s" },
    { "camera", "MOTION_DETECTION", "bool", "", "", "" , "", "", "ipc_cmd -O %s" },
    { "camera", "SENSITIVITY", "enum", "low", "medium", "high" , "", "", "ipc_cmd -s %s" },
    { "camera", "AI_HUMAN_DETECTION", "bool", "", "", "" , "", "", "ipc_cmd -a %s" },
    { "camera", "AI_VEHICLE_DETECTION", "bool", "", "", "" , "", "", "ipc_cmd -E %s" },
    { "camera", "AI_ANIMAL_DETECTION", "bool", "", "", "" , "", "", "ipc_cmd -N %s" },
    { "camera", "FACE_DETECTION", "bool", "", "", "" , "", "", "ipc_cmd -c %s" },
    { "camera", "BABY_CRYING_DETECT", "bool", "", "", "" , "", "", "ipc_cmd -B %s" },
    { "camera", "LED", "bool", "", "", "" , "", "", "ipc_cmd -l %s" },
    { "camera", "ROTATE", "bool", "", "", "" , "", "", "ipc_cmd -r %s" },
    { "camera", "IR", "bool", "", "", "", "", "", "ipc_cmd -i %s" },
    { "camera", "MIC", "bool", "", "", "", "", "", "ipc_cmd -I %s" },
    { "camera", "SOUND_DETECTION", "bool", "", "", "", "", "", "ipc_cmd -b %s" },
    { "camera", "SOUND_SENSITIVITY", "int", "30", "90", "", "", "", "ipc_cmd -n %s" },
    { "camera", "MOTION_TRACKING", "bool", "", "", "", "", "", "ipc_cmd -o %s" },
    { "camera", "CRUISE", "enum", "no", "presets", "360", "", "", "ipc_cmd -C %s" },

    { "ptz", "MOVE", "enum", "right", "left", "down", "up", "stop", "QUERY_STRING=\"action=step&dir=%s\" /home/yi-hack/www/cgi-bin/ptz.sh" },
    { "ptz", "GOTO_PRESET", "int", "0", "7", "", "", "", "/home/yi-hack/script/ptz_presets.sh -a go_preset -n %s" },
    { "ptz", "ADD_PRESET", "string", "", "", "", "", "", "/home/yi-hack/script/ptz_presets.sh -a add_preset -m %s" },
    { "ptz", "SET_HOME_POSITION", "string", "", "", "", "", "", "/home/yi-hack/script/ptz_presets.sh -a set_home_position" },
    { "ptz", "REMOVE_PRESET", "int", "0", "7", "", "", "", "/home/yi-hack/script/ptz_presets.sh -a del_preset -n %s" },
};

/* Always in step with the table above - adding a row can no longer desynchronise
 * a count that lives somewhere else. */
const int config_params_num = (int)(sizeof(config_params) / sizeof(config_params[0]));

int validate_param(char *file, char *key, char *value)
{
    int i, j;
    long long_low, long_high, long_value;
    int validate = 0;
    int errno;
    char *endptr;

    /* Look up on the (section, key) PAIR. The key alone does not identify a row:
     * ENABLED, PORT, USER, PASSWORD and STREAM each appear in several sections.
     * Matching on the key and then rejecting a section mismatch meant only the
     * FIRST row carrying a given key was ever reachable - e.g. services/snapshot
     * ENABLED shadowed services/rtsp ENABLED, and recording STREAM shadows
     * services/rtsp STREAM - so those settings could not be changed over MQTT. */
    for (i = 0; i < config_params_num; i++) {
        if ((strcasecmp(key, config_params[i][1]) == 0) &&
                (strcasecmp(file, config_params[i][0]) == 0)) {
            if (strcasecmp("bool", config_params[i][2]) == 0) {
                if ((strcmp(value, "yes") == 0) || (strcmp(value, "no") == 0)) {
                    validate = 1;
                }
                if ((strcmp(value, "on") == 0) || (strcmp(value, "off") == 0)) {
                    validate = 1;
                }
            } else if (strcasecmp("int", config_params[i][2]) == 0) {
                // Convert low limit string to int
                errno = 0;    /* To distinguish success/failure after call */
                long_low = strtol(config_params[i][3], &endptr, 10);
                validate = 1;

                /* Check for various possible errors */
                if ((errno == ERANGE && (long_low == LONG_MAX || long_low == LONG_MIN)) || (errno != 0 && long_low == 0)) {
                    validate = 0;
                }
                if (endptr == config_params[i][3]) {
                    validate = 0;
                }

                if (validate == 0) return validate;

                // Convert high limit string to int
                errno = 0;    /* To distinguish success/failure after call */
                long_high = strtol(config_params[i][4], &endptr, 10);
                validate = 1;

                /* Check for various possible errors */
                if ((errno == ERANGE && (long_high == LONG_MAX || long_high == LONG_MIN)) || (errno != 0 && long_high == 0)) {
                    validate = 0;
                }
                if (endptr == config_params[i][4]) {
                    validate = 0;
                }

                if (validate == 0) return validate;

                // Convert value string to int
                errno = 0;    /* To distinguish success/failure after call */
                long_value = strtol(value, &endptr, 10);
                validate = 1;

                /* Check for various possible errors */
                if ((errno == ERANGE && (long_value == LONG_MAX || long_value == LONG_MIN)) || (errno != 0 && long_value == 0)) {
                    validate = 0;
                }
                if (endptr == value) {
                    validate = 0;
                }

                if ((long_value < long_low) || (long_value > long_high)) {
                    validate = 0;
                }

            } else if (strcasecmp("string", config_params[i][2]) == 0) {
                validate = 1;
                if (strlen(value) >= PARAM_SIZE) {
                    validate = 0;
                }
            } else if (strcasecmp("enum", config_params[i][2]) == 0) {
                validate = 0;
                for (j = 3; j < PARAM_OPTIONS - 1; j++) {
                    if (config_params[i][j][0] == '\0') {
                        break;
                    }
                    if (strcmp(value, config_params[i][j]) == 0 ) {
                        validate = 1;
                        break;
                    }
                }
            }
            break;
        }
    }

    return validate;
}

int extract_param(char *param, char *file, char *key, int index)
{
    int i;
    int ret = -1;

    /* (section, key) pair, for the same reason as validate_param above. */
    for (i = 0; i < config_params_num; i++) {
        if ((strcasecmp(key, config_params[i][1]) == 0) &&
                (strcasecmp(file, config_params[i][0]) == 0)) {
            strcpy(param, config_params[i][index]);
            ret = 0;
            break;
        }
    }

    return ret;
}
