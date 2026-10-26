/*
 * This file is part of libipc (https://github.com/TheCrypt0/libipc).
 * Copyright (c) 2019 roleo.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

/*
 * Send message to a IPC queue.
 */

#include "ipc_cmd.h"
#include "ptz.h"
#include "getopt.h"
#include "signal.h"
#include "math.h"

mqd_t ipc_mq;

int open_queue()
{
    ipc_mq = mq_open(IPC_QUEUE_NAME, O_RDWR);
    if(ipc_mq == -1) {
        fprintf(stderr, "Can't open mqueue %s\n", IPC_QUEUE_NAME);
        return -1;
    }
    return 0;
}

int ipc_start()
{
    int ret = -1;

    ret = open_queue();
    if(ret != 0) {
        return -1;
    }

    return 0;
}

void ipc_stop()
{
    if(ipc_mq > 0) {
        mq_close(ipc_mq);
    }
}

/* PTZ without dispatch (native pipeline). Degrees use the same scale as -g.
 *
 * Presets live only in ptz_presets.conf ("N=name,x,y" in degrees), which
 * ptz_presets.sh already maintains from -g in both modes; dispatch's own copy is
 * what we lack here, so -P/-R/-H have nothing left to do and -p reads the file.
 *
 * Cruise is a small daemon (pid in CRUISE_PID_FILE). Manual moves touch
 * PTZ_MANUAL_FILE and the daemon pauses until they have been quiet for
 * CRUISE_RESUME_S, so it does not fight whoever is steering. */
#define PTZ_PRESETS_FILE "/home/yi-hack/config/ptz_presets.conf"
#define CRUISE_PID_FILE  "/tmp/ptz_cruise.pid"
#define PTZ_MANUAL_FILE  "/tmp/ptz_manual"
#define CRUISE_STAY_S    10
#define CRUISE_RESUME_S  60

/* campipe's motion detector ignores frames while this exists, so a turn of
 * ours (cruise, tracking) does not read as motion. */
#define PTZ_MOVING_MARKER MARKER_DIR "/ptz_moving"

static int marked_jump(int x, int y)
{
    int fd = open(PTZ_MOVING_MARKER, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    int ret;

    if (fd >= 0)
        close(fd);
    ret = native_ptz_jump(x, y);
    usleep(800 * 1000);         /* let the picture settle */
    unlink(PTZ_MOVING_MARKER);
    return ret;
}

static int native_jump_deg(double x, double y)
{
    return native_ptz_jump((int) round(x * MAX_PTZ_X / 360.0), (int) round(y * MAX_PTZ_Y / 180.0));
}

static int read_preset(int num, double *x, double *y)
{
    FILE *f = fopen(PTZ_PRESETS_FILE, "r");
    char line[128], *p;
    int n, ret = -1;

    if (f == NULL)
        return -1;
    while (fgets(line, sizeof(line), f) != NULL) {
        if (sscanf(line, "%d=", &n) != 1 || n != num)
            continue;
        p = strchr(line, ',');
        if (p != NULL && sscanf(p + 1, "%lf,%lf", x, y) == 2)
            ret = 0;
        break;
    }
    fclose(f);
    return ret;
}

static void touch_manual()
{
    int fd = open(PTZ_MANUAL_FILE, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0)
        close(fd);
}

static void cruise_pause(int secs)
{
    struct stat st;

    for (; secs > 0; secs--)
        sleep(1);
    while (stat(PTZ_MANUAL_FILE, &st) == 0 && time(NULL) - st.st_mtime < CRUISE_RESUME_S)
        sleep(1);
}

/* Stop the daemon whose pid is in pid_file; returns 1 if there was one. */
static int daemon_stop(const char *pid_file)
{
    FILE *f = fopen(pid_file, "r");
    int pid;

    if (f == NULL)
        return 0;
    if (fscanf(f, "%d", &pid) == 1 && pid > 1)
        kill(pid, SIGTERM);
    fclose(f);
    unlink(pid_file);
    return 1;
}

/* Returns in the parent (0) and in the detached child (1), which owns pid_file. */
static int daemon_start(const char *pid_file)
{
    FILE *f;

    if (fork() != 0)
        return 0;
    setsid();
    if (fork() != 0)
        exit(EXIT_SUCCESS);
    signal(SIGHUP, SIG_IGN);
    chdir("/");
    /* callers (mqtt-config, CGI) may wait for EOF on our stdout */
    freopen("/dev/null", "r", stdin);
    freopen("/dev/null", "w", stdout);
    freopen("/dev/null", "w", stderr);

    f = fopen(pid_file, "w");
    if (f != NULL) {
        fprintf(f, "%d\n", getpid());
        fclose(f);
    }
    return 1;
}

static void cruise_stop()
{
    if (daemon_stop(CRUISE_PID_FILE))
        native_ptz_stop();
}

static int cruise_start(int mode)
{
    double x, y;
    int i, found, cur_x, cur_y;

    cruise_stop();
    if (!daemon_start(CRUISE_PID_FILE))
        return 0;

    while (1) {
        if (mode == CRUISE_PRESETS) {
            found = 0;
            for (i = 0; i < 8; i++) {
                if (read_preset(i, &x, &y) != 0)
                    continue;
                found = 1;
                cruise_pause(0);
                marked_jump((int) round(x * MAX_PTZ_X / 360.0), (int) round(y * MAX_PTZ_Y / 180.0));
                cruise_pause(CRUISE_STAY_S);
            }
            if (!found)
                sleep(CRUISE_STAY_S);
        } else {
            /* 360: sweep end to end at the current tilt */
            for (i = 0; i < 2; i++) {
                cruise_pause(0);
                if (read_ptz(&cur_x, &cur_y) == 0)
                    marked_jump(i == 0 ? INT_MAX : 0, cur_y);
                cruise_pause(CRUISE_STAY_S / 2);
            }
        }
    }
    return 0;
}

/* Native settings persistence. In stock mode mqttv4 sees each command on
 * dispatch's queue, records it in camera.conf and publishes the new state; with
 * no queue that never happens, so the HA switches snapped back and boot could not
 * restore the setting. Do both here for the settings handled natively. */
#define CAMERA_CONF_FILE "/home/yi-hack/config/camera.conf"
#define CONF2MQTT_SCRIPT "/home/yi-hack/extra/script/conf2mqtt.sh"

static int camera_conf_set(const char *key, const char *value)
{
    char line[256], tmp[] = CAMERA_CONF_FILE ".tmp";
    FILE *in, *out;
    size_t klen = strlen(key);
    int changed = 0;

    in = fopen(CAMERA_CONF_FILE, "r");
    if (in == NULL)
        return 0;
    out = fopen(tmp, "w");
    if (out == NULL) {
        fclose(in);
        return 0;
    }
    while (fgets(line, sizeof(line), in) != NULL) {
        if (strncmp(line, key, klen) == 0 && line[klen] == '=') {
            line[strcspn(line, "\r\n")] = '\0';
            if (strcmp(line + klen + 1, value) != 0)
                changed = 1;
            fprintf(out, "%s=%s\n", key, value);
        } else {
            fputs(line, out);
        }
    }
    fclose(in);
    fclose(out);
    /* rewrite the flash only on a real change */
    if (changed)
        rename(tmp, CAMERA_CONF_FILE);
    else
        unlink(tmp);
    return changed;
}

static void native_persist(int ir, int mic, int cruise, int tracking,
                           int sound, int sound_sens, int babycrying)
{
    int changed = 0;
    char val[8];

    if (ir != NONE)
        changed |= camera_conf_set("IR", ir == IR_ON ? "yes" : "no");
    if (mic != NONE)
        changed |= camera_conf_set("MIC", mic == MIC_ON ? "yes" : "no");
    if (cruise != NONE)
        changed |= camera_conf_set("CRUISE", cruise == CRUISE_PRESETS ? "presets" :
                                   (cruise == CRUISE_OFF ? "no" : "360"));
    if (tracking != NONE)
        changed |= camera_conf_set("MOTION_TRACKING", tracking == MOTION_TRACKING_ON ? "yes" : "no");
    /* campipe's sound detector re-reads these from camera.conf */
    if (sound != NONE)
        changed |= camera_conf_set("SOUND_DETECTION", sound == SOUND_DETECTION_ON ? "yes" : "no");
    if (sound_sens != NONE) {
        snprintf(val, sizeof(val), "%d", sound_sens);
        changed |= camera_conf_set("SOUND_SENSITIVITY", val);
    }
    if (babycrying != NONE)
        changed |= camera_conf_set("BABY_CRYING_DETECT", babycrying == BABYCRYING_ON ? "yes" : "no");
    /* always republish: HA shows the requested state until it hears back */
    if (ir != NONE || mic != NONE || cruise != NONE || tracking != NONE ||
            sound != NONE || sound_sens != NONE || babycrying != NONE)
        system(CONF2MQTT_SCRIPT " camera >/dev/null 2>&1 &");
    (void) changed;
}

/* Motion tracking. campipe's detector keeps MOTION_XY_FILE at "<seq> <x> <y>"
 * (centre of the motion, permille of the frame); when it is off-centre we turn
 * towards it (marked_jump, so the detector ignores our own turn).
 * After TRACK_HOME_S without motion we go back to preset 0 (Home), if set.
 *
 * TRACK_FOV_X/Y: the frame width/height in driver units (27 steps each),
 * measured on the h20 (centre of the wide-angle lens; the edges are compressed). */
#define TRACK_PID_FILE    "/tmp/ptz_track.pid"
#define MOTION_XY_FILE    MARKER_DIR "/motion_xy"
#define TRACK_FOV_X       1000
#define TRACK_FOV_Y       300
#define TRACK_DEAD_ZONE   150     /* permille off-centre we tolerate */
#define TRACK_GAIN        80      /* percent of the offset to correct per step */
#define TRACK_HOME_S      30

static int read_motion_xy(unsigned int *seq, int *x, int *y)
{
    FILE *f = fopen(MOTION_XY_FILE, "r");
    int n;

    if (f == NULL)
        return -1;
    n = fscanf(f, "%u %d %d", seq, x, y);
    fclose(f);
    return n == 3 ? 0 : -1;
}

static void track_jump(int x, int y)
{
    touch_manual();             /* pause the cruise, if any */
    marked_jump(x, y);
}

static int track_start()
{
    unsigned int seq, last_seq = 0;
    int mx, my, cur_x, cur_y, dx, dy, away = 0;
    time_t last_motion = 0;
    double hx, hy;

    daemon_stop(TRACK_PID_FILE);
    if (!daemon_start(TRACK_PID_FILE))
        return 0;
    if (read_motion_xy(&seq, &mx, &my) == 0)
        last_seq = seq;         /* only react to motion from now on */

    while (1) {
        usleep(200 * 1000);
        if (read_motion_xy(&seq, &mx, &my) == 0 && seq != last_seq) {
            last_seq = seq;
            last_motion = time(NULL);
            dx = mx - 500;
            dy = my - 500;
            if (abs(dx) < TRACK_DEAD_ZONE && abs(dy) < TRACK_DEAD_ZONE)
                continue;
            if (read_ptz(&cur_x, &cur_y) != 0)
                continue;
            /* motion right of centre -> pan right, which lowers x; below -> raise y */
            if (abs(dx) < TRACK_DEAD_ZONE)
                dx = 0;
            if (abs(dy) < TRACK_DEAD_ZONE)
                dy = 0;
            track_jump(cur_x - dx * TRACK_FOV_X / 1000 * TRACK_GAIN / 100,
                       cur_y + dy * TRACK_FOV_Y / 1000 * TRACK_GAIN / 100);
            away = 1;
            /* updates written before the turn describe the old view */
            if (read_motion_xy(&seq, &mx, &my) == 0)
                last_seq = seq;
        } else if (away && time(NULL) - last_motion >= TRACK_HOME_S) {
            away = 0;
            if (read_preset(0, &hx, &hy) == 0)
                track_jump((int) round(hx * MAX_PTZ_X / 360.0), (int) round(hy * MAX_PTZ_Y / 180.0));
        }
    }
    return 0;
}

int native_ptz(int move, int jump_abs, int jump_rel, double x, double y, int get_pos, int calibrate,
               int preset, int cruise, int tracking)
{
    int cur_x, cur_y;

    if (calibrate)
        return native_ptz_calibrate();

    if (cruise == CRUISE_OFF)
        cruise_stop();
    else if (cruise == CRUISE_PRESETS || cruise == CRUISE_360 || cruise == CRUISE_ON)
        return cruise_start(cruise == CRUISE_PRESETS ? CRUISE_PRESETS : CRUISE_360);

    if (tracking == MOTION_TRACKING_OFF) {
        daemon_stop(TRACK_PID_FILE);
        unlink(PTZ_MOVING_MARKER);
    } else if (tracking == MOTION_TRACKING_ON) {
        return track_start();
    }

    if (move != NONE || jump_abs || jump_rel || preset != NONE)
        touch_manual();

    if (move == MOVE_STOP)
        return native_ptz_stop();
    if (move == MOVE_UP)
        return native_ptz_move(NATIVE_UP);
    if (move == MOVE_DOWN)
        return native_ptz_move(NATIVE_DOWN);
    if (move == MOVE_LEFT)
        return native_ptz_move(NATIVE_LEFT);
    if (move == MOVE_RIGHT)
        return native_ptz_move(NATIVE_RIGHT);

    if (preset != NONE) {
        if (read_preset(preset, &x, &y) != 0) {
            fprintf(stderr, "Preset %d not set\n", preset);
            return -1;
        }
        return native_jump_deg(x, y);
    }

    if (jump_abs || jump_rel || get_pos) {
        if (read_ptz(&cur_x, &cur_y) != 0) {
            fprintf(stderr, "Error reading current ptz position\n");
            return -1;
        }
    }
    if (jump_abs)
        return native_jump_deg(x, y);
    if (jump_rel)
        return native_ptz_jump(cur_x + (int) round(x * MAX_PTZ_X / 360.0), cur_y + (int) round(y * MAX_PTZ_Y / 180.0));
    if (get_pos) {
        fprintf(stderr, "Current x  = %d, y  = %d\n", cur_x, cur_y);
        fprintf(stdout, "%.1f,%.1f\n", ((double) cur_x) / MAX_PTZ_X * 360.0, ((double) cur_y) / MAX_PTZ_Y * 180.0);
    }
    return 0;
}

void print_usage(char *progname)
{
    fprintf(stderr, "\nUsage: %s [t ON/OFF] [-s SENS] [-l LED] [-v WHEN] [-i IR] [-r ROTATE] [-1] [-a AIHUMANDETECTION] [-E AIVEHICLEDETECTION] [-N AIANIMALDETECTION] [-O AIMOTIONDETECTION] [-c FACEDETECTION] [-o MOTIONTRACKING] [-I MIC] [-b SOUNDDETECTION] [-B BABYCRYING] [-n SOUNDSENSITIVITY] [-m MOVE] [-g] [-j ABS_POSITION] [-J REL_POSITION] [-p NUM] [-P NAME] [-R NUM] [-C MODE] [-f FILE] [-S TIME] [-T] [-d]\n\n", progname);
    fprintf(stderr, "\t-t ON/OFF, --switch ON/OFF\n");
    fprintf(stderr, "\t\tswitch ON or OFF the cam\n");
    fprintf(stderr, "\t-s SENS, --sensitivity SENS\n");
    fprintf(stderr, "\t\tset sensitivity: LOW, MEDIUM or HIGH\n");
    fprintf(stderr, "\t-l LED, --led LED\n");
    fprintf(stderr, "\t\tset led: ON or OFF\n");
    fprintf(stderr, "\t-v WHEN, --save WHEN\n");
    fprintf(stderr, "\t\tset save mode: ALWAYS or DETECT\n");
    fprintf(stderr, "\t-i IR, --ir IR\n");
    fprintf(stderr, "\t\tset ir led: ON or OFF\n");
    fprintf(stderr, "\t-r ROTATE, --rotate ROTATE\n");
    fprintf(stderr, "\t\tset rotate: ON or OFF\n");
    fprintf(stderr, "\t-1, --setalertallowstate_human\n");
    fprintf(stderr, "\t\tset alert allow state to human\n");
    fprintf(stderr, "\t-a AIHUMANDETECTION, --aihumandetection AIHUMANDETECTION\n");
    fprintf(stderr, "\t\tset AI Human Detection: ON or OFF\n");
    fprintf(stderr, "\t-E AIVEHICLEDETECTION, --aivehicledetection AIVEHICLEDETECTION\n");
    fprintf(stderr, "\t\tset AI Vehicle Detection: ON or OFF\n");
    fprintf(stderr, "\t-N AIANIMALDETECTION, --aianimaldetection AIANIMALDETECTION\n");
    fprintf(stderr, "\t\tset AI Animal Detection: ON or OFF\n");
    fprintf(stderr, "\t-O AIMOTIONDETECTION, --aimotiondetection AIMOTIONDETECTION\n");
    fprintf(stderr, "\t\tset AI Motion Detection: ON or OFF (disable all other AI detections)\n");
    fprintf(stderr, "\t-c FACEDETECTION, --facedetection FACEDETECTION\n");
    fprintf(stderr, "\t\tset Face Detection: ON or OFF\n");
    fprintf(stderr, "\t-o MOTIONTRACKING, --motiontracking MOTIONTRACKING\n");
    fprintf(stderr, "\t\tset Motion Tracking sensor: ON or OFF\n");
    fprintf(stderr, "\t-I MIC, --mic MIC\n");
    fprintf(stderr, "\t\tset Microphone: ON or OFF\n");
    fprintf(stderr, "\t-b SOUNDDETECTION, --sounddetection SOUNDDETECTION\n");
    fprintf(stderr, "\t\tset Sound Detection: ON or OFF\n");
    fprintf(stderr, "\t-B BABYCRYING, --babycrying BABYCRYING\n");
    fprintf(stderr, "\t\tset baby crying detection: ON or OFF\n");
    fprintf(stderr, "\t-n SOUNDSENSITIVITY, --soundsensitivity SOUNDSENSITIVITY\n");
    fprintf(stderr, "\t\tset Sound Detection Sensitivity: 30 - 90\n");
    fprintf(stderr, "\t-m MOVE, --move MOVE\n");
    fprintf(stderr, "\t\tsend PTZ command: RIGHT, LEFT, DOWN, UP or STOP\n");
    fprintf(stderr, "\t-g, --get-ptz\n");
    fprintf(stderr, "\t\tget PTZ position\n");
    fprintf(stderr, "\t-j ABS_POSITION, --jump-abs ABS_POSITION\n");
    fprintf(stderr, "\t\tmove PTZ to ABS_POSITION (x,y) in degrees (example -j 500,500)\n");
    fprintf(stderr, "\t-J REL_POSITION, --jump-rel REL_POSITION\n");
    fprintf(stderr, "\t\tmove PTZ to REL_POSITION (x,y) in degrees (example -J 500,500)\n");
    fprintf(stderr, "\t-K, --calibrate\n");
    fprintf(stderr, "\t\tfind the PTZ end stops and centre (native pipeline only)\n");
    fprintf(stderr, "\t-p NUM, --preset NUM\n");
    fprintf(stderr, "\t\tsend PTZ go to preset command: TOKEN = [0..7]\n");
    fprintf(stderr, "\t-P NAME, --add_preset NAME\n");
    fprintf(stderr, "\t\tadd PTZ preset with name NAME in the first available position\n");
    fprintf(stderr, "\t-H, --set_home_position\n");
    fprintf(stderr, "\t\tset home position (preset 0 for Yi cam)\n");
    fprintf(stderr, "\t-R NUM, --remove_preset NUM\n");
    fprintf(stderr, "\t\tremove PTZ preset: NUM = [0..7] or \"all\"\n");
    fprintf(stderr, "\t-C MODE, --cruise MODE\n");
    fprintf(stderr, "\t\tset cruise mode: \"on\", \"off\", \"presets\" or \"360\"\n");
    fprintf(stderr, "\t-f FILE, --file FILE\n");
    fprintf(stderr, "\t\tread binary command from FILE\n");
    fprintf(stderr, "\t-S TIME, --start_motion TIME\n");
    fprintf(stderr, "\t\tstart a motion detection event that lasts TIME\n");
    fprintf(stderr, "\t\t(0<TIME<=300 seconds)\n");
    fprintf(stderr, "\t-T, --stop_motion\n");
    fprintf(stderr, "\t\tstop a motion detection event\n");
    fprintf(stderr, "\t-d, --debug\n");
    fprintf(stderr, "\t\tenable debug\n");
    fprintf(stderr, "\t-h, --help\n");
    fprintf(stderr, "\t\tprint this help\n");
}

int main(int argc, char ** argv)
{
    int errno;
    char *endptr;
    int c, ret, i;
    int switch_on = NONE;
    int sensitivity = NONE;
    int led = NONE;
    int save = NONE;
    int ir = NONE;
    int rotate = NONE;
    int setalertallowstate_human = NONE;
    int aihumandetection = NONE;
    int aivehicledetection = NONE;
    int aianimaldetection = NONE;
    int aimotiondetection = NONE;
    int facedetection = NONE;
    int motiontracking = NONE;
    int mic = NONE;
    int sounddetection = NONE;
    int babycrying = NONE;
    int soundsensitivity = NONE;
    int move = NONE;
    int get_pos = NONE;
    int calibrate = NONE;
    int jump_abs = NONE;
    int jump_rel = NONE;
    char jump_msg[24];
    double x, y;
    int preset = NONE;
    int add_preset = NONE;
    int set_home_position = NONE;
    int remove_preset = NONE;
    int cruise = NONE;
    int debug = 0;
    unsigned char preset_msg[20];
    int start = 0;
    int stop = 0;
    int time_to_stop = 60;
    char file[1024];
    unsigned char msg_file[1024];
    FILE *fIn;
    int nread = 0;
    int xxx_0 = 0;

    file[0] = '\0';

    while (1) {
        static struct option long_options[] =
        {
            {"switch",  required_argument, 0, 't'},
            {"sensitivity",  required_argument, 0, 's'},
            {"led",  required_argument, 0, 'l'},
            {"save",  required_argument, 0, 'v'},
            {"ir",  required_argument, 0, 'i'},
            {"rotate",  required_argument, 0, 'r'},
            {"setalertallowstate_human",  no_argument, 0, '1'},
            {"aihumandetection",  required_argument, 0, 'a'},
            {"aivehicledetection",  required_argument, 0, 'E'},
            {"aianimaldetection",  required_argument, 0, 'N'},
            {"aimotiondetection",  required_argument, 0, 'O'},
            {"facedetection",  required_argument, 0, 'c'},
            {"motiontracking",  required_argument, 0, 'o'},
            {"mic",  required_argument, 0, 'I'},
            {"sounddetection",  required_argument, 0, 'b'},
            {"babycrying",  required_argument, 0, 'B'},
            {"soundsensitivity",  required_argument, 0, 'n'},
            {"move",  required_argument, 0, 'm'},
            {"move-reverse",  required_argument, 0, 'M'},
            {"get-pos", no_argument, 0, 'g'},
            {"jump-abs", required_argument, 0, 'j'},
            {"jump-rel", required_argument, 0, 'J'},
            {"calibrate", no_argument, 0, 'K'},
            {"preset",  required_argument, 0, 'p'},
            {"add_preset",  required_argument, 0, 'P'},
            {"set_home_position",  no_argument, 0, 'H'},
            {"remove_preset",  required_argument, 0, 'R'},
            {"cruise",  required_argument, 0, 'C'},
            {"file", required_argument, 0, 'f'},
            {"start", required_argument, 0, 'S'},
            {"stop", no_argument, 0, 'T'},
            {"xxx", no_argument, 0, 'x'},
            {"debug",  no_argument, 0, 'd'},
            {"help",  no_argument, 0, 'h'},
            {0, 0, 0, 0}
        };
        /* getopt_long stores the option index here. */
        int option_index = 0;

        c = getopt_long (argc, argv, "t:s:l:v:i:r:a:E:N:O:c:o:I:b:B:n:m:M:gj:J:Kp:P:HR:C:f:S:Txdh",
                         long_options, &option_index);

        /* Detect the end of the options. */
        if (c == -1)
            break;

        switch (c) {
        case 't':
            if ((strcasecmp("off", optarg) == 0) || (strcasecmp("no", optarg) == 0)) {
                switch_on = SWITCH_OFF;
            } else if ((strcasecmp("on", optarg) == 0) || (strcasecmp("yes", optarg) == 0)) {
                switch_on = SWITCH_ON;
            } else {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 's':
            if (strcasecmp("low", optarg) == 0) {
                sensitivity = SENSITIVITY_LOW;
            } else if (strcasecmp("medium", optarg) == 0) {
                sensitivity = SENSITIVITY_MEDIUM;
            } else if (strcasecmp("high", optarg) == 0) {
                sensitivity = SENSITIVITY_HIGH;
            } else {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'l':
            if ((strcasecmp("off", optarg) == 0) || (strcasecmp("no", optarg) == 0)) {
                led = LED_OFF;
            } else if ((strcasecmp("on", optarg) == 0) || (strcasecmp("yes", optarg) == 0)) {
                led = LED_ON;
            } else {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'v':
            if ((strcasecmp("always", optarg) == 0) || (strcasecmp("off", optarg) == 0) || (strcasecmp("no", optarg) == 0)) {
                save = SAVE_ALWAYS;
            } else if ((strcasecmp("detect", optarg) == 0) || (strcasecmp("on", optarg) == 0) || (strcasecmp("yes", optarg) == 0)) {
                save = SAVE_DETECT;
            } else {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'i':
            if ((strcasecmp("off", optarg) == 0) || (strcasecmp("no", optarg) == 0)) {
                ir = IR_OFF;
            } else if ((strcasecmp("on", optarg) == 0) || (strcasecmp("yes", optarg) == 0)) {
                ir = IR_ON;
            } else {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'r':
            if ((strcasecmp("off", optarg) == 0) || (strcasecmp("no", optarg) == 0)) {
                rotate = ROTATE_OFF;
            } else if ((strcasecmp("on", optarg) == 0) || (strcasecmp("yes", optarg) == 0)) {
                rotate = ROTATE_ON;
            } else {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case '1':
            setalertallowstate_human = 1;
            break;

        case 'a':
            if ((strcasecmp("off", optarg) == 0) || (strcasecmp("no", optarg) == 0)) {
                aihumandetection = AI_HUMAN_DETECTION_OFF;
            } else if ((strcasecmp("on", optarg) == 0) || (strcasecmp("yes", optarg) == 0)) {
                aihumandetection = AI_HUMAN_DETECTION_ON;
            } else {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'E':
            if ((strcasecmp("off", optarg) == 0) || (strcasecmp("no", optarg) == 0)) {
                aivehicledetection = AI_VEHICLE_DETECTION_OFF;
            } else if ((strcasecmp("on", optarg) == 0) || (strcasecmp("yes", optarg) == 0)) {
                aivehicledetection = AI_VEHICLE_DETECTION_ON;
            } else {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'N':
            if ((strcasecmp("off", optarg) == 0) || (strcasecmp("no", optarg) == 0)) {
                aianimaldetection = AI_ANIMAL_DETECTION_OFF;
            } else if ((strcasecmp("on", optarg) == 0) || (strcasecmp("yes", optarg) == 0)) {
                aianimaldetection = AI_ANIMAL_DETECTION_ON;
            } else {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'O':
            if ((strcasecmp("off", optarg) == 0) || (strcasecmp("no", optarg) == 0)) {
                aimotiondetection = AI_MOTION_DETECTION_OFF;
            } else if ((strcasecmp("on", optarg) == 0) || (strcasecmp("yes", optarg) == 0)) {
                aimotiondetection = AI_MOTION_DETECTION_ON;
            } else {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'c':
            if ((strcasecmp("off", optarg) == 0) || (strcasecmp("no", optarg) == 0)) {
                facedetection = FACE_DETECTION_OFF;
            } else if ((strcasecmp("on", optarg) == 0) || (strcasecmp("yes", optarg) == 0)) {
                facedetection = FACE_DETECTION_ON;
            } else {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'o':
            if ((strcasecmp("off", optarg) == 0) || (strcasecmp("no", optarg) == 0)) {
                motiontracking = MOTION_TRACKING_OFF;
            } else if ((strcasecmp("on", optarg) == 0) || (strcasecmp("yes", optarg) == 0)) {
                motiontracking = MOTION_TRACKING_ON;
            } else {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'I':
            if ((strcasecmp("off", optarg) == 0) || (strcasecmp("no", optarg) == 0)) {
                mic = MIC_OFF;
            } else if ((strcasecmp("on", optarg) == 0) || (strcasecmp("yes", optarg) == 0)) {
                mic = MIC_ON;
            } else {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'b':
            if ((strcasecmp("off", optarg) == 0) || (strcasecmp("no", optarg) == 0)) {
                sounddetection = SOUND_DETECTION_OFF;
            } else if ((strcasecmp("on", optarg) == 0) || (strcasecmp("yes", optarg) == 0)) {
                sounddetection = SOUND_DETECTION_ON;
            } else {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'B':
            if ((strcasecmp("off", optarg) == 0) || (strcasecmp("no", optarg) == 0)) {
                babycrying = BABYCRYING_OFF;
            } else if ((strcasecmp("on", optarg) == 0) || (strcasecmp("yes", optarg) == 0)) {
                babycrying = BABYCRYING_ON;
            }
            break;

        case 'n':
            if (strcasecmp("30", optarg) == 0) {
                soundsensitivity = SOUND_SENS_30;
            } else if (strcasecmp("35", optarg) == 0) {
                soundsensitivity = SOUND_SENS_35;
            } else if (strcasecmp("40", optarg) == 0) {
                soundsensitivity = SOUND_SENS_40;
            } else if (strcasecmp("45", optarg) == 0) {
                soundsensitivity = SOUND_SENS_45;
            } else if (strcasecmp("50", optarg) == 0) {
                soundsensitivity = SOUND_SENS_50;
            } else if (strcasecmp("60", optarg) == 0) {
                soundsensitivity = SOUND_SENS_60;
            } else if (strcasecmp("70", optarg) == 0) {
                soundsensitivity = SOUND_SENS_70;
            } else if (strcasecmp("80", optarg) == 0) {
                soundsensitivity = SOUND_SENS_80;
            } else if (strcasecmp("90", optarg) == 0) {
                soundsensitivity = SOUND_SENS_90;
            } else {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'm':
            if (strcasecmp("right", optarg) == 0) {
                move = MOVE_RIGHT;
            } else if (strcasecmp("left", optarg) == 0) {
                move = MOVE_LEFT;
            } else if (strcasecmp("down", optarg) == 0) {
                move = MOVE_DOWN;
            } else if (strcasecmp("up", optarg) == 0) {
                move = MOVE_UP;
            } else if (strcasecmp("stop", optarg) == 0) {
                move = MOVE_STOP;
            } else {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'M':
            if (strcasecmp("right", optarg) == 0) {
                move = MOVE_LEFT;
            } else if (strcasecmp("left", optarg) == 0) {
                move = MOVE_RIGHT;
            } else if (strcasecmp("down", optarg) == 0) {
                move = MOVE_UP;
            } else if (strcasecmp("up", optarg) == 0) {
                move = MOVE_DOWN;
            } else if (strcasecmp("stop", optarg) == 0) {
                move = MOVE_STOP;
            } else {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'g':
            get_pos = 1;
            break;

        case 'K':
            calibrate = 1;
            break;

        case 'j':
            jump_abs = 1;
            if (sscanf(optarg, "%lf,%lf", &x, &y) != 2) {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            if ((x < 0.0) || (x > 360.0)) {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            if ((y < 0.0) || (y > 180.0)) {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'J':
            jump_rel = 1;
            if (sscanf(optarg, "%lf,%lf", &x, &y) != 2) {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            if ((x < -360.0) || (x > 360.0)) {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            if ((y < -180.0) || (y > 180.0)) {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'p':
            errno = 0;    /* To distinguish success/failure after call */
            preset = strtol(optarg, &endptr, 10);

            /* Check for various possible errors */
            if ((errno == ERANGE && (preset == LONG_MAX || preset == LONG_MIN)) || (errno != 0 && preset == 0)) {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            if (endptr == optarg) {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'P':
            // Ignore argument
            add_preset = 1;
            break;

        case 'H':
            set_home_position = 1;
            break;

        case 'R':
            errno = 0;    /* To distinguish success/failure after call */
            if (strcasecmp("all", optarg) == 0) {
                remove_preset = 255;
            } else {
                remove_preset = strtol(optarg, &endptr, 10);

                /* Check for various possible errors */
                if ((errno == ERANGE && (remove_preset == LONG_MAX || remove_preset == LONG_MIN)) || (errno != 0 && remove_preset == 0)) {
                    print_usage(argv[0]);
                    exit(EXIT_FAILURE);
                }
                if (endptr == optarg) {
                    print_usage(argv[0]);
                    exit(EXIT_FAILURE);
                }
            }
            if ((remove_preset != 255) && ((remove_preset < 0) || (remove_preset > 7))) {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'C':
            if ((strcasecmp("off", optarg) == 0) || (strcasecmp("no", optarg) == 0)) {
                cruise = CRUISE_OFF;
            } else if ((strcasecmp("on", optarg) == 0) || (strcasecmp("yes", optarg) == 0)) {
                cruise = CRUISE_ON;
            } else if (strcasecmp("presets", optarg) == 0) {
                cruise = CRUISE_PRESETS;
            } else if (strcasecmp("360", optarg) == 0) {
                cruise = CRUISE_360;
            } else {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'f':
            /* Check for various possible errors */
            if (strlen(optarg) < 1023) {
                strcpy(file, optarg);
            } else {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            break;

        case 'S':
            errno = 0;    /* To distinguish success/failure after call */
            time_to_stop = strtol(optarg, &endptr, 10);

            /* Check for various possible errors */
            if ((errno == ERANGE && (time_to_stop == LONG_MAX || time_to_stop == LONG_MIN)) || (errno != 0 && time_to_stop == 0)) {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            if ((time_to_stop <= 0) || (time_to_stop > 300)) {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            if (endptr == optarg) {
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
            }
            start = 1;
            break;

        case 'T':
            stop = 1;
            break;

        case 'd':
            fprintf (stderr, "debug on\n");
            debug = 1;
            break;

        case 'x':
            xxx_0 = 1;
            break;

        case 'h':
            print_usage(argv[0]);
            exit(EXIT_SUCCESS);
            break;

        case '?':
            /* getopt_long already printed an error message. */
            break;

        default:
            print_usage(argv[0]);
            exit(EXIT_SUCCESS);
        }
    }

    if (argc == 1) {
        print_usage(argv[0]);
        exit(EXIT_SUCCESS);
    }

    /* Mic mute is the one setting the NATIVE pipeline can honour too, so publish
     * it on the local marker-file bus before touching the stock queue: campipe
     * watches MIC_MUTE_MARKER and mutes the codec ADC. Done unconditionally and
     * up front because it must also work when the queue below is absent - in
     * native mode rmm never runs, so mq_open fails and this program used to exit
     * before doing anything, which is why the MIC toggle was a no-op there. In
     * stock mode the marker is simply unread and rmm still gets its message. */
    if (mic != NONE) {
        mkdir(MARKER_DIR, 0755);
        if (mic == MIC_OFF) {
            int fd = open(MIC_MUTE_MARKER, O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (fd >= 0)
                close(fd);
            else
                fprintf(stderr, "Can't create %s: %s\n", MIC_MUTE_MARKER, strerror(errno));
        } else if (unlink(MIC_MUTE_MARKER) != 0 && errno != ENOENT) {
            fprintf(stderr, "Can't remove %s: %s\n", MIC_MUTE_MARKER, strerror(errno));
        }
    }

    /* Same for the IR illuminator: campipe's day/night keeps it dark at night
     * while IR_OFF_MARKER exists. */
    if (ir != NONE) {
        mkdir(MARKER_DIR, 0755);
        if (ir == IR_OFF) {
            int fd = open(IR_OFF_MARKER, O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (fd >= 0)
                close(fd);
            else
                fprintf(stderr, "Can't create %s: %s\n", IR_OFF_MARKER, strerror(errno));
        } else if (unlink(IR_OFF_MARKER) != 0 && errno != ENOENT) {
            fprintf(stderr, "Can't remove %s: %s\n", IR_OFF_MARKER, strerror(errno));
        }
    }

    ret=ipc_start();
    if(ret != 0) {
        /* No dispatch queue: the native pipeline. PTZ still works by driving the
         * motor driver directly; everything else needs the stock stack. */
        native_persist(ir, mic, cruise, motiontracking, sounddetection, soundsensitivity, babycrying);
        if (native_ptz_available() &&
                (move != NONE || jump_abs != NONE || jump_rel != NONE || get_pos != NONE || calibrate != NONE ||
                 preset != NONE || add_preset != NONE || remove_preset != NONE || set_home_position != NONE ||
                 cruise != NONE || motiontracking != NONE)) {
            exit(native_ptz(move, jump_abs != NONE, jump_rel != NONE, x, y, get_pos != NONE, calibrate != NONE,
                            preset, cruise, motiontracking) == 0 ? EXIT_SUCCESS : EXIT_FAILURE);
        }
        /* -i/-I were handled above through the marker files, -b/-n/-B by persisting */
        exit((ir != NONE || mic != NONE || sounddetection != NONE || soundsensitivity != NONE ||
              babycrying != NONE) ? EXIT_SUCCESS : EXIT_FAILURE);
    }

    if (switch_on == SWITCH_ON) {
        mq_send(ipc_mq, IPC_SWITCH_ON, sizeof(IPC_SWITCH_ON) - 1, 0);
    } else if (switch_on == SWITCH_OFF) {
        mq_send(ipc_mq, IPC_SWITCH_OFF, sizeof(IPC_SWITCH_OFF) - 1, 0);
    }

    if (sensitivity == SENSITIVITY_LOW) {
        mq_send(ipc_mq, IPC_SENS_LOW, sizeof(IPC_SENS_LOW) - 1, 0);
    } else if (sensitivity == SENSITIVITY_MEDIUM) {
        mq_send(ipc_mq, IPC_SENS_MEDIUM, sizeof(IPC_SENS_MEDIUM) - 1, 0);
    } else if (sensitivity == SENSITIVITY_HIGH) {
        mq_send(ipc_mq, IPC_SENS_HIGH, sizeof(IPC_SENS_HIGH) - 1, 0);
    }

    if (led == LED_OFF) {
        mq_send(ipc_mq, IPC_LED_OFF, sizeof(IPC_LED_OFF) - 1, 0);
    } else if (led == LED_ON) {
        mq_send(ipc_mq, IPC_LED_ON, sizeof(IPC_LED_ON) - 1, 0);
    }

    if (save == SAVE_ALWAYS) {
        mq_send(ipc_mq, IPC_SAVE_ALWAYS, sizeof(IPC_SAVE_ALWAYS) - 1, 0);
    } else if (save == SAVE_DETECT) {
        mq_send(ipc_mq, IPC_SAVE_DETECT, sizeof(IPC_SAVE_DETECT) - 1, 0);
    }

    if (ir == IR_OFF) {
        mq_send(ipc_mq, IPC_IR_OFF, sizeof(IPC_IR_OFF) - 1, 0);
    } else if (ir == IR_ON) {
        mq_send(ipc_mq, IPC_IR_ON, sizeof(IPC_IR_ON) - 1, 0);
    }

    if (rotate == ROTATE_OFF) {
        mq_send(ipc_mq, IPC_ROTATE_OFF, sizeof(IPC_ROTATE_OFF) - 1, 0);
    } else if (rotate == ROTATE_ON) {
        mq_send(ipc_mq, IPC_ROTATE_ON, sizeof(IPC_ROTATE_ON) - 1, 0);
    }

    if (setalertallowstate_human == 1) {
        mq_send(ipc_mq, IPC_SET_ALERT_ALLOW_STATE_HUMAN, sizeof(IPC_SET_ALERT_ALLOW_STATE_HUMAN) - 1, 0);
    }

    if (aihumandetection == AI_HUMAN_DETECTION_OFF) {
        mq_send(ipc_mq, IPC_AI_HUMAN_DETECTION_OFF, sizeof(IPC_AI_HUMAN_DETECTION_OFF) - 1, 0);
    } else if (aihumandetection == AI_HUMAN_DETECTION_ON) {
        mq_send(ipc_mq, IPC_AI_HUMAN_DETECTION_ON, sizeof(IPC_AI_HUMAN_DETECTION_ON) - 1, 0);
    }

    if (aivehicledetection == AI_VEHICLE_DETECTION_OFF) {
        mq_send(ipc_mq, IPC_AI_VEHICLE_DETECTION_OFF, sizeof(IPC_AI_VEHICLE_DETECTION_OFF) - 1, 0);
    } else if (aivehicledetection == AI_VEHICLE_DETECTION_ON) {
        mq_send(ipc_mq, IPC_AI_VEHICLE_DETECTION_ON, sizeof(IPC_AI_VEHICLE_DETECTION_ON) - 1, 0);
    }

    if (aianimaldetection == AI_ANIMAL_DETECTION_OFF) {
        mq_send(ipc_mq, IPC_AI_ANIMAL_DETECTION_OFF, sizeof(IPC_AI_ANIMAL_DETECTION_OFF) - 1, 0);
    } else if (aianimaldetection == AI_ANIMAL_DETECTION_ON) {
        mq_send(ipc_mq, IPC_AI_ANIMAL_DETECTION_ON, sizeof(IPC_AI_ANIMAL_DETECTION_ON) - 1, 0);
    }

    if (aimotiondetection == AI_MOTION_DETECTION_OFF) {
        mq_send(ipc_mq, IPC_AI_MOTION_DETECTION_OFF, sizeof(IPC_AI_MOTION_DETECTION_OFF) - 1, 0);
    } else if (aimotiondetection == AI_MOTION_DETECTION_ON) {
        mq_send(ipc_mq, IPC_AI_MOTION_DETECTION_ON, sizeof(IPC_AI_MOTION_DETECTION_ON) - 1, 0);
    }

    if (facedetection == FACE_DETECTION_OFF) {
        mq_send(ipc_mq, IPC_FACE_DETECTION_OFF, sizeof(IPC_FACE_DETECTION_OFF) - 1, 0);
    } else if (facedetection == FACE_DETECTION_ON) {
        mq_send(ipc_mq, IPC_FACE_DETECTION_ON, sizeof(IPC_FACE_DETECTION_ON) - 1, 0);
    }

    if (motiontracking == MOTION_TRACKING_OFF) {
        mq_send(ipc_mq, IPC_MOTION_TRACKING_OFF, sizeof(IPC_MOTION_TRACKING_OFF) - 1, 0);
    } else if (motiontracking == MOTION_TRACKING_ON) {
        mq_send(ipc_mq, IPC_MOTION_TRACKING_ON, sizeof(IPC_MOTION_TRACKING_ON) - 1, 0);
    }

    if (mic == MIC_OFF) {
        mq_send(ipc_mq, IPC_MIC_OFF, sizeof(IPC_MIC_OFF) - 1, 0);
    } else if (mic == MIC_ON) {
        mq_send(ipc_mq, IPC_MIC_ON, sizeof(IPC_MIC_ON) - 1, 0);
    }

    if (sounddetection == SOUND_DETECTION_OFF) {
        mq_send(ipc_mq, IPC_SOUND_DETECTION_OFF, sizeof(IPC_SOUND_DETECTION_OFF) - 1, 0);
    } else if (sounddetection == SOUND_DETECTION_ON) {
        mq_send(ipc_mq, IPC_SOUND_DETECTION_ON, sizeof(IPC_SOUND_DETECTION_ON) - 1, 0);
    }

    if (babycrying == BABYCRYING_OFF) {
        mq_send(ipc_mq, IPC_BABYCRYING_OFF, sizeof(IPC_BABYCRYING_OFF) - 1, 0);
    } else if (babycrying == BABYCRYING_ON) {
        mq_send(ipc_mq, IPC_BABYCRYING_ON, sizeof(IPC_BABYCRYING_ON) - 1, 0);
    }

    if (soundsensitivity == SOUND_SENS_30) {
        mq_send(ipc_mq, IPC_SOUND_SENS_30, sizeof(IPC_SOUND_SENS_30) - 1, 0);
    } else if (soundsensitivity == SOUND_SENS_35) {
        mq_send(ipc_mq, IPC_SOUND_SENS_35, sizeof(IPC_SOUND_SENS_35) - 1, 0);
    } else if (soundsensitivity == SOUND_SENS_40) {
        mq_send(ipc_mq, IPC_SOUND_SENS_40, sizeof(IPC_SOUND_SENS_40) - 1, 0);
    } else if (soundsensitivity == SOUND_SENS_45) {
        mq_send(ipc_mq, IPC_SOUND_SENS_45, sizeof(IPC_SOUND_SENS_45) - 1, 0);
    } else if (soundsensitivity == SOUND_SENS_50) {
        mq_send(ipc_mq, IPC_SOUND_SENS_50, sizeof(IPC_SOUND_SENS_50) - 1, 0);
    } else if (soundsensitivity == SOUND_SENS_60) {
        mq_send(ipc_mq, IPC_SOUND_SENS_60, sizeof(IPC_SOUND_SENS_60) - 1, 0);
    } else if (soundsensitivity == SOUND_SENS_70) {
        mq_send(ipc_mq, IPC_SOUND_SENS_70, sizeof(IPC_SOUND_SENS_70) - 1, 0);
    } else if (soundsensitivity == SOUND_SENS_80) {
        mq_send(ipc_mq, IPC_SOUND_SENS_80, sizeof(IPC_SOUND_SENS_80) - 1, 0);
    } else if (soundsensitivity == SOUND_SENS_90) {
        mq_send(ipc_mq, IPC_SOUND_SENS_90, sizeof(IPC_SOUND_SENS_90) - 1, 0);
    }

    if (move != NONE) {
        char model_suffix[16];
        int is_ptz_value;

        memset(model_suffix, '\0', sizeof(model_suffix));
        get_model_suffix(model_suffix, sizeof(model_suffix));
        is_ptz_value = is_ptz(model_suffix);

        if (is_ptz_value == ALLWINNER_V2) {
            move = -1 * move;
        } else if ((is_ptz_value == ALLWINNER_V2_ALT) &&
                ((move == MOVE_LEFT) || (move == MOVE_RIGHT))) {
            move = -1 * move;
        }

        if (move == MOVE_RIGHT) {
            mq_send(ipc_mq, IPC_MOVE_RIGHT, sizeof(IPC_MOVE_RIGHT) - 1, 0);
        } else if (move == MOVE_LEFT) {
            mq_send(ipc_mq, IPC_MOVE_LEFT, sizeof(IPC_MOVE_LEFT) - 1, 0);
        } else if (move == MOVE_DOWN) {
            mq_send(ipc_mq, IPC_MOVE_DOWN, sizeof(IPC_MOVE_DOWN) - 1, 0);
        } else if (move == MOVE_UP) {
            mq_send(ipc_mq, IPC_MOVE_UP, sizeof(IPC_MOVE_UP) - 1, 0);
        } else if (move == MOVE_STOP) {
            mq_send(ipc_mq, IPC_MOVE_STOP, sizeof(IPC_MOVE_STOP) - 1, 0);
        }
    }

    if (jump_abs != NONE) {
        double fx, fy;
        int cur_x, cur_y;
        int fin_x, fin_y;
        char model_suffix[16];
        int is_ptz_value;

        memset(model_suffix, '\0', sizeof(model_suffix));
        get_model_suffix(model_suffix, sizeof(model_suffix));
        is_ptz_value = is_ptz(model_suffix);

        if (is_ptz_value == ALLWINNER_V2_ALT) {
            y = 180.0 - y;
        }

        if (read_ptz(&cur_x, &cur_y) != 0) {
            fprintf(stderr, "Error reading current ptz position\n");
            return -1;
        }
        fx = x * (((double) MAX_PTZ_X) / 360.0);
        fx = round(fx);
        fx = (fx - ((double) cur_x)) * 100.0 / 911.0 + 50.0;
        fin_x = (int) round(fx);
        fy = y * (((double) MAX_PTZ_Y) / 180.0);
        fy = round(fy);
        fy = (fy - ((double) cur_y)) * 100.0 / 694.0 + 50.0;
        fin_y = (int) round(fy);

        if (debug) fprintf(stderr, "Current x  = %d, y  = %d\n", cur_x, cur_y);
        if (debug) fprintf(stderr, "Command xr = %d, yr = %d\n", fin_x, fin_y);
        memcpy(jump_msg, IPC_JUMP_POSITION, sizeof(IPC_JUMP_POSITION) - 1);
        memcpy(&jump_msg[16], &fin_x, 4);
        memcpy(&jump_msg[20], &fin_y, 4);
        mq_send(ipc_mq, jump_msg, sizeof(IPC_JUMP_POSITION) - 1, 0);
    }

    if (jump_rel != NONE) {
        double fx, fy;
        int cur_x, cur_y;
        int fin_x, fin_y;
        char model_suffix[16];
        int is_ptz_value;

        memset(model_suffix, '\0', sizeof(model_suffix));
        get_model_suffix(model_suffix, sizeof(model_suffix));
        is_ptz_value = is_ptz(model_suffix);

        if (is_ptz_value == ALLWINNER_V2_ALT) {
            y = -1.0 * y;
        }

        if (read_ptz(&cur_x, &cur_y) != 0) {
            fprintf(stderr, "Error reading current ptz position\n");
            return -1;
        }
        fx = x * (((double) MAX_PTZ_X) / 360.0);
        fx = round(fx);
        fx = fx * 100.0 / 911.0 + 50.0;
        fin_x = (int) round(fx);
        fy = y * (((double) MAX_PTZ_Y) / 180.0);
        fy = round(fy);
        fy = fy * 100.0 / 694.0 + 50.0;
        fin_y = (int) round(fy);

        if (debug) fprintf(stderr, "Current x  = %d, y  = %d\n", cur_x, cur_y);
        if (debug) fprintf(stderr, "Command xr = %d, yr = %d\n", fin_x, fin_y);
        memcpy(jump_msg, IPC_JUMP_POSITION, sizeof(IPC_JUMP_POSITION) - 1);
        memcpy(&jump_msg[16], &fin_x, 4);
        memcpy(&jump_msg[20], &fin_y, 4);
        mq_send(ipc_mq, jump_msg, sizeof(IPC_JUMP_POSITION) - 1, 0);
    }

    if (preset != NONE) {
        memcpy(preset_msg, IPC_GOTO_PRESET, sizeof(IPC_GOTO_PRESET) - 1);
        preset_msg[16] = preset & 0xff;
        mq_send(ipc_mq, preset_msg, sizeof(IPC_GOTO_PRESET) - 1, 0);
    }

    if (add_preset != NONE) {
        // Ignore name because Yi doesn't support it
        mq_send(ipc_mq, IPC_ADD_PRESET, sizeof(IPC_ADD_PRESET) - 1, 0);
    }

    if (get_pos != NONE) {
        double fx, fy;
        int cur_x, cur_y;
        char model_suffix[16];
        int is_ptz_value;

        memset(model_suffix, '\0', sizeof(model_suffix));
        get_model_suffix(model_suffix, sizeof(model_suffix));
        is_ptz_value = is_ptz(model_suffix);

        if (read_ptz(&cur_x, &cur_y) != 0) {
            fprintf(stderr, "Error reading current ptz position\n");
            return -1;
        }
        fprintf(stderr, "Current x  = %d, y  = %d\n", cur_x, cur_y);
        fx = ((double) cur_x) / ((double) MAX_PTZ_X) * 360.0;
        fy = ((double) cur_y) / ((double) MAX_PTZ_Y) * 180.0;
        if (is_ptz_value == ALLWINNER_V2_ALT) {
            fy = 180.0 - fy;
        }

        fprintf(stderr, "Degrees x  = %.1f, y  = %.1f\n", fx, fy);
        fprintf(stdout, "%.1f,%.1f\n", fx, fy);
    }

    if (set_home_position != NONE) {
        // Remove preset 0
        memcpy(preset_msg, IPC_REMOVE_PRESET, sizeof(IPC_REMOVE_PRESET) - 1);
        preset_msg[16] = 0;
        mq_send(ipc_mq, preset_msg, sizeof(IPC_REMOVE_PRESET) - 1, 0);
        // sleep 1 sec and add it again
        sleep(1);
        mq_send(ipc_mq, IPC_ADD_PRESET, sizeof(IPC_ADD_PRESET) - 1, 0);
    }

    if (remove_preset != NONE) {
        if (remove_preset == 255) {
            for (i = 0; i < 8; i++) {
                memcpy(preset_msg, IPC_REMOVE_PRESET, sizeof(IPC_REMOVE_PRESET) - 1);
                preset_msg[16] = i & 0xff;
                mq_send(ipc_mq, preset_msg, sizeof(IPC_REMOVE_PRESET) - 1, 0);
            }
        } else {
            memcpy(preset_msg, IPC_REMOVE_PRESET, sizeof(IPC_REMOVE_PRESET) - 1);
            preset_msg[16] = remove_preset & 0xff;
            mq_send(ipc_mq, preset_msg, sizeof(IPC_REMOVE_PRESET) - 1, 0);
        }
    }

    if (cruise != NONE) {
        if (cruise == CRUISE_OFF) {
            mq_send(ipc_mq, IPC_CRUISE_OFF, sizeof(IPC_CRUISE_OFF) - 1, 0);
        } else if (cruise == CRUISE_ON) {
            mq_send(ipc_mq, IPC_CRUISE_ON, sizeof(IPC_CRUISE_ON) - 1, 0);
        } else if (cruise == CRUISE_PRESETS) {
            mq_send(ipc_mq, IPC_CRUISE_ON, sizeof(IPC_CRUISE_ON) - 1, 0);
            usleep(100 * 1000);
            mq_send(ipc_mq, IPC_CRUISE_PRESETS, sizeof(IPC_CRUISE_PRESETS) - 1, 0);
        } else if (cruise == CRUISE_360) {
            mq_send(ipc_mq, IPC_CRUISE_ON, sizeof(IPC_CRUISE_ON) - 1, 0);
            usleep(100 * 1000);
            mq_send(ipc_mq, IPC_CRUISE_360, sizeof(IPC_CRUISE_360) - 1, 0);
        }
    }

    if (file[0] != '\0') {
        fIn = fopen(file, "r");
        if (fIn == NULL) {
            fprintf(stderr, "Error opening file %s\n", file);
            exit(EXIT_FAILURE);
        }

        // Tell size
        fseek(fIn, 0L, SEEK_END);
        nread = ftell(fIn);
        fseek(fIn, 0L, SEEK_SET);

        if (fread(msg_file, 1, nread, fIn) != nread) {
            fprintf(stderr, "Error reading file %s\n", file);
            fclose(fIn);
            exit(EXIT_FAILURE);
        }
        fclose(fIn);
        mq_send(ipc_mq, msg_file, nread, 0);
    }

    if (start == 1) {
        mq_send(ipc_mq, IPC_MOTION_START, sizeof(IPC_MOTION_START) - 1, 0);

        pid_t pid;

        /* Fork off the parent process */
        pid = fork();
        /* An error occurred */
        if (pid < 0)
            exit(EXIT_FAILURE);
         /* Success: Let the parent terminate */
        if (pid > 0)
            exit(EXIT_SUCCESS);
        /* On success: The child process becomes session leader */
        if (setsid() < 0)
            exit(EXIT_FAILURE);
        /* Catch, ignore and handle signals */
        signal(SIGCHLD, SIG_IGN);
        signal(SIGHUP, SIG_IGN);
        /* Fork off for the second time*/
        pid = fork();
        /* An error occurred */
        if (pid < 0)
            exit(EXIT_FAILURE);
        /* Success: Let the parent terminate */
        if (pid > 0)
            exit(EXIT_SUCCESS);
        /* Set new file permissions */
        umask(0);
        /* Change the working directory to the root directory */
        /* or another appropriated directory */
        chdir("/");
        /* Close all open file descriptors */
//        int x;
//        for (x = sysconf(_SC_OPEN_MAX); x>=0; x--) {
//            close (x);
//        }

        sleep(time_to_stop);
        mq_send(ipc_mq, IPC_MOTION_STOP, sizeof(IPC_MOTION_STOP) - 1, 0);
    }

    if (stop == 1) {
        mq_send(ipc_mq, IPC_MOTION_STOP, sizeof(IPC_MOTION_STOP) - 1, 0);
    }

    if (xxx_0 == 1) {
        mq_send(ipc_mq, IPC_XXX_0, sizeof(IPC_XXX_0) - 1, 0);
    }

    ipc_stop();

    return 0;
}
