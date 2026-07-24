/*
 * This file is part of libipc (https://github.com/TheCrypt0/libipc).
 * Copyright (c) 2019 Davide Maggioni.
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
 *
 * Copyright (c) 2026 Lino Barreca (https://github.com/LinoBarreca/yi-hack-v6).
 */

#include "ipc.h"

#include <sys/inotify.h>
#include <sys/stat.h>
#include <poll.h>

/* Motion delivery = a marker file on the local event bus (/tmp/ipc). campipe
 * (native mode) or ipc2file (stock mode) creates motion_alarm on the start edge
 * and removes it on stop; we watch the directory with inotify and drive the same
 * motion callbacks. Motion therefore works identically in both pipeline modes,
 * and the mqueue (which only exists in stock mode) is no longer motion's source
 * — see parse_message. The mqueue still carries the stock-only AI/sound/command
 * events, and its absence in native mode is non-fatal (see ipc_init). */
#define IPC_EVENT_DIR    "/tmp/ipc"
#define IPC_MOTION_FILE  "motion_alarm"

//-----------------------------------------------------------------------------
// GENERAL STATIC VARS AND FUNCTIONS
//-----------------------------------------------------------------------------

char *ipc_cmd_params[][2] = {
    { "switch_on",            "no"      },    //IPC_CMD_SWITCH_OFF,
    { "switch_on",            "yes"     },    //IPC_CMD_SWITCH_ON,
    { "save_video_on_motion", "no"      },    //IPC_CMD_SAVE_ALWAYS,
    { "save_video_on_motion", "yes"     },    //IPC_CMD_SAVE_DETECT,
    { "motion_detection",     "no"      },    //IPC_CMD_AI_MOTION_DETECTION_OFF,
    { "motion_detection",     "yes"     },    //IPC_CMD_AI_MOTION_DETECTION_ON,
    { "sensitivity",          "high"    },    //IPC_CMD_SENS_HIGH,
    { "sensitivity",          "medium"  },    //IPC_CMD_SENS_MEDIUM,
    { "sensitivity",          "low"     },    //IPC_CMD_SENS_LOW,
    { "ai_human_detection",   "no"      },    //IPC_CMD_AI_HUMAN_DETECTION_OFF,
    { "ai_human_detection",   "yes"     },    //IPC_CMD_AI_HUMAN_DETECTION_ON,
    { "ai_vehicle_detection", "no"      },    //IPC_CMD_AI_VEHICLE_DETECTION_OFF,
    { "ai_vehicle_detection", "yes"     },    //IPC_CMD_AI_VEHICLE_DETECTION_ON,
    { "ai_animal_detection",  "no"      },    //IPC_CMD_AI_ANIMAL_DETECTION_OFF,
    { "ai_animal_detection",  "yes"     },    //IPC_CMD_AI_ANIMAL_DETECTION_ON,
    { "face_detection",       "no"      },    //IPC_CMD_FACE_DETECTION_OFF,
    { "face_detection",       "yes"     },    //IPC_CMD_FACE_DETECTION_ON ,
    { "motion_tracking",      "no"      },    //IPC_CMD_MOTION_TRACKING_OFF,
    { "motion_tracking",      "yes"     },    //IPC_CMD_MOTION_TRACKING_ON,
    { "baby_crying_detect",   "no"      },    //IPC_CMD_BABYCRYING_OFF,
    { "baby_crying_detect",   "yes"     },    //IPC_CMD_BABYCRYING_ON,
    { "sound_detection",      "no"      },    //IPC_CMD_SOUND_DETECTION_OFF,
    { "sound_detection",      "yes"     },    //IPC_CMD_SOUND_DETECTION_ON,
    { "sound_sensitivity",    "30"      },    //IPC_CMD_SOUND_SENS_30,
    { "sound_sensitivity",    "35"      },    //IPC_CMD_SOUND_SENS_35,
    { "sound_sensitivity",    "40"      },    //IPC_CMD_SOUND_SENS_40,
    { "sound_sensitivity",    "45"      },    //IPC_CMD_SOUND_SENS_45,
    { "sound_sensitivity",    "50"      },    //IPC_CMD_SOUND_SENS_50,
    { "sound_sensitivity",    "60"      },    //IPC_CMD_SOUND_SENS_60,
    { "sound_sensitivity",    "70"      },    //IPC_CMD_SOUND_SENS_70,
    { "sound_sensitivity",    "80"      },    //IPC_CMD_SOUND_SENS_80,
    { "sound_sensitivity",    "90"      },    //IPC_CMD_SOUND_SENS_90,
    { "led",                  "no"      },    //IPC_CMD_LED_OFF,
    { "led",                  "yes"     },    //IPC_CMD_LED_ON,
    { "ir",                   "no"      },    //IPC_CMD_IR_OFF,
    { "ir",                   "yes"     },    //IPC_CMD_IR_ON ,
    { "rotate",               "no"      },    //IPC_CMD_ROTATE_OFF,
    { "rotate",               "yes"     },    //IPC_CMD_ROTATE_ON,
    { "cruise",               "no"      },    //IPC_CMD_CRUISE_OFF,
    { "cruise",               "yes"     },    //IPC_CMD_CRUISE_ON,
    { "cruise",               "presets" },    //IPC_CMD_CRUISE_PRESETS,
    { "cruise",               "360"     },    //IPC_CMD_CRUISE_360,
    { "mic",                  "no"      },    //IPC_CMD_MIC_OFF,
    { "mic",                  "yes"     },    //IPC_CMD_MIC_ON,
    { "",                     ""        }     //IPC_CMD_LAST
};

static mqd_t ipc_mq;
static int ipc_mq_ok;                 /* 0 when the mqueue is absent (native mode) */
static pthread_t *tr_queue;
int tr_queue_routine;
static pthread_t *tr_inotify;
static int tr_inotify_routine;

static int open_queue();
static int clear_queue();
static int start_queue_thread();
static void *queue_thread(void *args);
static int start_inotify_thread();
static void *inotify_thread(void *args);
static int parse_message(char *msg, ssize_t len);

static void call_callback(IPC_MESSAGE_TYPE type);
static void call_callback_cmd(IPC_COMMAND_TYPE type);
static void ipc_debug(const char* fmt, ...);

//-----------------------------------------------------------------------------
// MESSAGES HANDLERS
//-----------------------------------------------------------------------------

static void handle_ipc_ai_human_detection();
static void handle_ipc_ai_vehicle_detection();
static void handle_ipc_ai_animal_detection();
static void handle_ipc_baby_crying();
static void handle_ipc_sound_detection();
static void handle_ipc_command(int cmd);

static void handle_ipc_unrecognized();

//-----------------------------------------------------------------------------
// FUNCTION POINTERS TO CALLBACKS
//-----------------------------------------------------------------------------

typedef void(*func_ptr_t)(void* arg);

static func_ptr_t *ipc_callbacks;

//=============================================================================

//-----------------------------------------------------------------------------
// INIT
//-----------------------------------------------------------------------------

int ipc_init()
{
    ipc_callbacks=malloc((sizeof(func_ptr_t))*IPC_MSG_LAST);

    /* The mqueue only exists in stock mode (ipc_multiplex.so creates it). In
     * native mode it is absent — that is NOT an error: motion arrives via the
     * inotify path below, and the mqueue-only events (AI/sound/command) simply
     * don't occur in native mode. So a missing queue is non-fatal; without this
     * mqttv4 would exit at boot in native mode and no MQTT would run at all. */
    ipc_mq_ok = 0;
    if(open_queue() == 0)
    {
        if(clear_queue() != 0)
            return -2;
        if(start_queue_thread() != 0)
            return -2;
        ipc_mq_ok = 1;
    }
    else
    {
        fprintf(stderr, "IPC mqueue %s absent - motion via inotify only\n",
                IPC_QUEUE_NAME);
    }

    /* Motion (both pipeline modes) comes from the marker file. */
    if(start_inotify_thread() != 0)
        return -2;

    return 0;
}

void ipc_stop()
{
    if(tr_inotify!=NULL)
    {
        tr_inotify_routine=0;
        pthread_join((*tr_inotify), NULL);
        free(tr_inotify);
    }

    if(tr_queue!=NULL)
    {
        tr_queue_routine=0;
        pthread_join((*tr_queue), NULL);
        free(tr_queue);
    }

    if(ipc_callbacks!=NULL)
        free(ipc_callbacks);

    if(ipc_mq_ok && ipc_mq>0)
        mq_close(ipc_mq);
}

//-----------------------------------------------------------------------------
// MQ_QUEUE STUFF
//-----------------------------------------------------------------------------

static int open_queue()
{
    ipc_mq=mq_open(IPC_QUEUE_NAME, O_RDWR);
    if(ipc_mq==-1)
    {
        fprintf(stderr, "Can't open mqueue %s. Error: %s\n", IPC_QUEUE_NAME,
                strerror(errno));
        return -1;
    }
    return 0;
}

static int clear_queue()
{
    struct mq_attr attr;
    char buffer[IPC_MESSAGE_MAX_SIZE + 1];

    if (mq_getattr(ipc_mq, &attr) == -1) {
        fprintf(stderr, "Can't get queue attributes\n");
        return -1;
    }

    while (attr.mq_curmsgs > 0) {
        ipc_debug("Clear message in queue...");
        mq_receive(ipc_mq, buffer, IPC_MESSAGE_MAX_SIZE, NULL);
        ipc_debug(" done.\n");
        if (mq_getattr(ipc_mq, &attr) == -1) {
            fprintf(stderr, "Can't get queue attributes\n");
            return -1;
        }
    }

    return 0;
}

static int start_queue_thread()
{
    int ret;

    tr_queue=malloc(sizeof(pthread_t));
    tr_queue_routine=1;
    ret=pthread_create(tr_queue, NULL, &queue_thread, NULL);
    if(ret!=0)
    {
        fprintf(stderr, "Can't create ipc thread. Error: %d\n", ret);
        return -1;
    }

    return 0;
}

static void *queue_thread(void *args)
{
    ssize_t bytes_read;
    char buffer[IPC_MESSAGE_MAX_SIZE];

    while(tr_queue_routine)
    {
        bytes_read=mq_receive(ipc_mq, buffer, IPC_MESSAGE_MAX_SIZE, NULL);

        ipc_debug("IPC message. Len: %d. Status: %s!\n", bytes_read,
                  strerror(errno));

        if(bytes_read>=0)
        {
            parse_message(buffer, bytes_read);
        }
        usleep(10*1000);
    }

    return 0;
}

//-----------------------------------------------------------------------------
// INOTIFY (MOTION MARKER FILE)
//-----------------------------------------------------------------------------

static int start_inotify_thread()
{
    tr_inotify = malloc(sizeof(pthread_t));
    tr_inotify_routine = 1;
    if(pthread_create(tr_inotify, NULL, &inotify_thread, NULL) != 0)
    {
        fprintf(stderr, "Can't create inotify thread.\n");
        free(tr_inotify);
        tr_inotify = NULL;
        return -1;
    }

    return 0;
}

static void *inotify_thread(void *args)
{
    int fd, wd;
    char path[256];
    struct stat st;
    /* inotify_event is variable-length; align the buffer to read a batch. */
    char buf[4096] __attribute__ ((aligned(__alignof__(struct inotify_event))));

    // campipe / ipc2file also create this, but we may start first.
    mkdir(IPC_EVENT_DIR, 0755);

    fd = inotify_init1(IN_NONBLOCK);
    if(fd < 0)
    {
        fprintf(stderr, "inotify_init1 failed: %s\n", strerror(errno));
        return 0;
    }
    wd = inotify_add_watch(fd, IPC_EVENT_DIR, IN_CREATE | IN_DELETE);
    if(wd < 0)
    {
        fprintf(stderr, "inotify_add_watch(%s) failed: %s\n", IPC_EVENT_DIR, strerror(errno));
        close(fd);
        return 0;
    }

    /* Recover current state: if the marker already exists at startup (motion in
     * progress when mqttv4 (re)started), fire a start so we're not stuck clear -
     * a transient mqueue message could never offer this. */
    snprintf(path, sizeof(path), "%s/%s", IPC_EVENT_DIR, IPC_MOTION_FILE);
    if(stat(path, &st) == 0)
        call_callback(IPC_MSG_MOTION_START);

    while(tr_inotify_routine)
    {
        struct pollfd pfd = { fd, POLLIN, 0 };
        ssize_t len;
        char *p;

        // Timed poll so we re-check tr_inotify_routine and can be joined.
        if(poll(&pfd, 1, 500) <= 0)
            continue;

        len = read(fd, buf, sizeof(buf));
        if(len <= 0)
            continue;

        for(p = buf; p < buf + len; )
        {
            struct inotify_event *e = (struct inotify_event *) p;
            if(e->len > 0 && strcmp(e->name, IPC_MOTION_FILE) == 0)
            {
                if(e->mask & IN_CREATE)
                    call_callback(IPC_MSG_MOTION_START);
                else if(e->mask & IN_DELETE)
                    call_callback(IPC_MSG_MOTION_STOP);
            }
            p += sizeof(struct inotify_event) + e->len;
        }
    }

    inotify_rm_watch(fd, wd);
    close(fd);

    return 0;
}

//-----------------------------------------------------------------------------
// IPC PARSER
//-----------------------------------------------------------------------------

static int parse_message(char *msg, ssize_t len)
{
    int i;
    ipc_debug("Parsing message.\n");

    for(i=0; i<len; i++)
        ipc_debug("%02x ", msg[i]);
    ipc_debug("\n");

    /* Motion is intentionally NOT parsed from the mqueue anymore: it arrives via
     * the inotify marker-file path (inotify_thread), which works in both stock
     * and native mode. Parsing it here too would double-fire in stock mode, where
     * ipc2file also writes the marker from the same mqueue message. The remaining
     * events below are stock-only and have no native-mode source. */
    if((len >= sizeof(IPC_AI_HUMAN_DETECTION) - 1) && (memcmp(msg, IPC_AI_HUMAN_DETECTION, sizeof(IPC_AI_HUMAN_DETECTION) - 1)==0))
    {
        handle_ipc_ai_human_detection();
        return 0;
    }
    else if((len >= sizeof(IPC_AI_BODY_DETECTION_C) - 1) && (memcmp(msg, IPC_AI_BODY_DETECTION_C, sizeof(IPC_AI_BODY_DETECTION_C) - 1)==0))
    {
        handle_ipc_ai_human_detection();
        return 0;
    }
    else if((len >= sizeof(IPC_AI_VEHICLE_DETECTION_C) - 1) && (memcmp(msg, IPC_AI_VEHICLE_DETECTION_C, sizeof(IPC_AI_VEHICLE_DETECTION_C) - 1)==0))
    {
        handle_ipc_ai_vehicle_detection();
        return 0;
    }
    else if((len >= sizeof(IPC_AI_ANIMAL_DETECTION_C) - 1) && (memcmp(msg, IPC_AI_ANIMAL_DETECTION_C, sizeof(IPC_AI_ANIMAL_DETECTION_C) - 1)==0))
    {
        handle_ipc_ai_animal_detection();
        return 0;
    }
    else if((len >= sizeof(IPC_BABY_CRYING) - 1) && (memcmp(msg, IPC_BABY_CRYING, sizeof(IPC_BABY_CRYING) - 1)==0))
    {
        handle_ipc_baby_crying();
        return 0;
    }
    else if((len >= sizeof(IPC_SOUND_DETECTION) - 1) && (memcmp(msg, IPC_SOUND_DETECTION, sizeof(IPC_SOUND_DETECTION) - 1)==0))
    {
        handle_ipc_sound_detection();
        return 0;
    }
    else if((len >= sizeof(IPC_SWITCH_OFF) - 1) && (memcmp(msg, IPC_SWITCH_OFF , sizeof(IPC_SWITCH_OFF) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_SWITCH_OFF);
        return 0;
    }
    else if((len >= sizeof(IPC_SWITCH_ON) - 1) && (memcmp(msg, IPC_SWITCH_ON, sizeof(IPC_SWITCH_ON) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_SWITCH_ON);
        return 0;
    }
    else if((len >= sizeof(IPC_SAVE_ALWAYS) - 1) && (memcmp(msg, IPC_SAVE_ALWAYS, sizeof(IPC_SAVE_ALWAYS) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_SAVE_ALWAYS);
        return 0;
    }
    else if((len >= sizeof(IPC_SAVE_DETECT) - 1) && (memcmp(msg, IPC_SAVE_DETECT, sizeof(IPC_SAVE_DETECT) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_SAVE_DETECT);
        return 0;
    }
    else if((len >= sizeof(IPC_AI_MOTION_DETECTION_OFF) - 1) && (memcmp(msg, IPC_AI_MOTION_DETECTION_OFF, sizeof(IPC_AI_MOTION_DETECTION_OFF ) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_AI_MOTION_DETECTION_OFF);
        return 0;
    }
    else if((len >= sizeof(IPC_AI_MOTION_DETECTION_ON) - 1) && (memcmp(msg, IPC_AI_MOTION_DETECTION_ON, sizeof(IPC_AI_MOTION_DETECTION_ON) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_AI_MOTION_DETECTION_ON);
        return 0;
    }
    else if((len >= sizeof(IPC_SENS_HIGH) - 1) && (memcmp(msg, IPC_SENS_HIGH, sizeof(IPC_SENS_HIGH) - 1)==0)){
        handle_ipc_command(IPC_CMD_SENS_HIGH);
        return 0;
    }
    else if((len >= sizeof(IPC_SENS_MEDIUM) - 1) && (memcmp(msg, IPC_SENS_MEDIUM, sizeof(IPC_SENS_MEDIUM) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_SENS_MEDIUM);
        return 0;
    }
    else if((len >= sizeof(IPC_SENS_LOW) - 1) && (memcmp(msg, IPC_SENS_LOW, sizeof(IPC_SENS_LOW) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_SENS_LOW);
        return 0;
    }
    else if((len >= sizeof(IPC_AI_HUMAN_DETECTION_OFF) - 1) && (memcmp(msg, IPC_AI_HUMAN_DETECTION_OFF, sizeof(IPC_AI_HUMAN_DETECTION_OFF) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_AI_HUMAN_DETECTION_OFF);
        return 0;
    }
    else if((len >= sizeof(IPC_AI_HUMAN_DETECTION_ON) - 1) && (memcmp(msg, IPC_AI_HUMAN_DETECTION_ON, sizeof(IPC_AI_HUMAN_DETECTION_ON) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_AI_HUMAN_DETECTION_ON);
        return 0;
    }
    else if((len >= sizeof(IPC_AI_VEHICLE_DETECTION_OFF) - 1) && (memcmp(msg, IPC_AI_VEHICLE_DETECTION_OFF, sizeof(IPC_AI_VEHICLE_DETECTION_OFF) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_AI_VEHICLE_DETECTION_OFF);
        return 0;
    }
    else if((len >= sizeof(IPC_AI_VEHICLE_DETECTION_ON) - 1) && (memcmp(msg, IPC_AI_VEHICLE_DETECTION_ON, sizeof(IPC_AI_VEHICLE_DETECTION_ON ) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_AI_VEHICLE_DETECTION_ON);
        return 0;
    }
    else if((len >= sizeof(IPC_AI_ANIMAL_DETECTION_OFF) - 1) && (memcmp(msg, IPC_AI_ANIMAL_DETECTION_OFF, sizeof(IPC_AI_ANIMAL_DETECTION_OFF ) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_AI_ANIMAL_DETECTION_OFF);
        return 0;
    }
    else if((len >= sizeof(IPC_AI_ANIMAL_DETECTION_ON) - 1) && (memcmp(msg, IPC_AI_ANIMAL_DETECTION_ON, sizeof(IPC_AI_ANIMAL_DETECTION_ON) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_AI_ANIMAL_DETECTION_ON);
        return 0;
    }
    else if((len >= sizeof(IPC_FACE_DETECTION_OFF) - 1) && (memcmp(msg, IPC_FACE_DETECTION_OFF, sizeof(IPC_FACE_DETECTION_OFF) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_FACE_DETECTION_OFF);
        return 0;
    }
    else if((len >= sizeof(IPC_FACE_DETECTION_ON) - 1) && (memcmp(msg, IPC_FACE_DETECTION_ON, sizeof(IPC_FACE_DETECTION_ON) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_FACE_DETECTION_ON);
        return 0;
    }
    else if((len >= sizeof(IPC_MOTION_TRACKING_OFF) - 1) && (memcmp(msg, IPC_MOTION_TRACKING_OFF, sizeof(IPC_MOTION_TRACKING_OFF) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_MOTION_TRACKING_OFF);
        return 0;
    }
    else if((len >= sizeof(IPC_MOTION_TRACKING_ON) - 1) && (memcmp(msg, IPC_MOTION_TRACKING_ON, sizeof(IPC_MOTION_TRACKING_ON) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_MOTION_TRACKING_ON);
        return 0;
    }
    else if((len >= sizeof(IPC_BABYCRYING_OFF) - 1) && (memcmp(msg, IPC_BABYCRYING_OFF, sizeof(IPC_BABYCRYING_OFF) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_BABYCRYING_OFF);
        return 0;
    }
    else if((len >= sizeof(IPC_BABYCRYING_ON) - 1) && (memcmp(msg, IPC_BABYCRYING_ON, sizeof(IPC_BABYCRYING_ON ) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_BABYCRYING_ON);
        return 0;
    }
    else if((len >= sizeof(IPC_SOUND_DETECTION_OFF) - 1) && (memcmp(msg, IPC_SOUND_DETECTION_OFF, sizeof(IPC_SOUND_DETECTION_OFF) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_SOUND_DETECTION_OFF);
        return 0;
    }
    else if((len >= sizeof(IPC_SOUND_DETECTION_ON) - 1) && (memcmp(msg, IPC_SOUND_DETECTION_ON, sizeof(IPC_SOUND_DETECTION_ON) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_SOUND_DETECTION_ON);
        return 0;
    }
    else if((len >= sizeof(IPC_SOUND_SENS_30) - 1) && (memcmp(msg, IPC_SOUND_SENS_30, sizeof(IPC_SOUND_SENS_30 ) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_SOUND_SENS_30);
        return 0;
    }
    else if((len >= sizeof(IPC_SOUND_SENS_35) - 1) && (memcmp(msg, IPC_SOUND_SENS_35, sizeof(IPC_SOUND_SENS_35 ) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_SOUND_SENS_35);
        return 0;
    }
    else if((len >= sizeof(IPC_SOUND_SENS_40) - 1) && (memcmp(msg, IPC_SOUND_SENS_40, sizeof(IPC_SOUND_SENS_40 ) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_SOUND_SENS_40);
        return 0;
    }
    else if((len >= sizeof(IPC_SOUND_SENS_45) - 1) && (memcmp(msg, IPC_SOUND_SENS_45, sizeof(IPC_SOUND_SENS_45 ) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_SOUND_SENS_45);
        return 0;
    }
    else if((len >= sizeof(IPC_SOUND_SENS_50) - 1) && (memcmp(msg, IPC_SOUND_SENS_50, sizeof(IPC_SOUND_SENS_50 ) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_SOUND_SENS_50);
        return 0;
    }
    else if((len >= sizeof(IPC_SOUND_SENS_60) - 1) && (memcmp(msg, IPC_SOUND_SENS_60, sizeof(IPC_SOUND_SENS_60 ) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_SOUND_SENS_60);
        return 0;
    }
    else if((len >= sizeof(IPC_SOUND_SENS_70) - 1) && (memcmp(msg, IPC_SOUND_SENS_70, sizeof(IPC_SOUND_SENS_70 ) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_SOUND_SENS_70);
        return 0;
    }
    else if((len >= sizeof(IPC_SOUND_SENS_80) - 1) && (memcmp(msg, IPC_SOUND_SENS_80, sizeof(IPC_SOUND_SENS_80 ) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_SOUND_SENS_80);
        return 0;
    }
    else if((len >= sizeof(IPC_SOUND_SENS_90) - 1) && (memcmp(msg, IPC_SOUND_SENS_90, sizeof(IPC_SOUND_SENS_90 ) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_SOUND_SENS_90);
        return 0;
    }
    else if((len >= sizeof(IPC_LED_OFF) - 1) && (memcmp(msg, IPC_LED_OFF, sizeof(IPC_LED_OFF) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_LED_OFF);
        return 0;
    }
    else if((len >= sizeof(IPC_LED_ON) - 1) && (memcmp(msg, IPC_LED_ON, sizeof(IPC_LED_ON) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_LED_ON);
        return 0;
    }
    else if((len >= sizeof(IPC_IR_OFF) - 1) && (memcmp(msg, IPC_IR_OFF, sizeof(IPC_IR_OFF) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_IR_OFF);
        return 0;
    }
    else if((len >= sizeof(IPC_IR_ON ) - 1) && (memcmp(msg, IPC_IR_ON, sizeof(IPC_IR_ON) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_IR_ON);
        return 0;
    }
    else if((len >= sizeof(IPC_MIC_OFF) - 1) && (memcmp(msg, IPC_MIC_OFF, sizeof(IPC_MIC_OFF) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_MIC_OFF);
        return 0;
    }
    else if((len >= sizeof(IPC_MIC_ON) - 1) && (memcmp(msg, IPC_MIC_ON, sizeof(IPC_MIC_ON) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_MIC_ON);
        return 0;
    }
    else if((len >= sizeof(IPC_ROTATE_OFF) - 1) && (memcmp(msg, IPC_ROTATE_OFF , sizeof(IPC_ROTATE_OFF) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_ROTATE_OFF);
        return 0;
    }
    else if((len >= sizeof(IPC_ROTATE_ON) - 1) && (memcmp(msg, IPC_ROTATE_ON, sizeof(IPC_ROTATE_ON) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_ROTATE_ON);
        return 0;
    }
    else if((len >= sizeof(IPC_CRUISE_OFF) - 1) && (memcmp(msg, IPC_CRUISE_OFF , sizeof(IPC_CRUISE_OFF) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_CRUISE_OFF);
        return 0;
    }
    else if((len >= sizeof(IPC_CRUISE_ON) - 1) && (memcmp(msg, IPC_CRUISE_ON, sizeof(IPC_CRUISE_ON) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_CRUISE_ON);
        return 0;
    }
    else if((len >= sizeof(IPC_CRUISE_PRESETS) - 1) && (memcmp(msg, IPC_CRUISE_PRESETS, sizeof(IPC_CRUISE_PRESETS) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_CRUISE_PRESETS);
        return 0;
    }
    else if((len >= sizeof(IPC_CRUISE_360) - 1) && (memcmp(msg, IPC_CRUISE_360 , sizeof(IPC_CRUISE_360) - 1)==0))
    {
        handle_ipc_command(IPC_CMD_CRUISE_360);
        return 0;
    }
    handle_ipc_unrecognized();

    return -1;
}

//-----------------------------------------------------------------------------
// IPC HANDLERS
//-----------------------------------------------------------------------------

static void handle_ipc_unrecognized()
{
    ipc_debug("GOT UNRECOGNIZED MESSAGE\n");
//    call_callback(IPC_MSG_UNRECOGNIZED);
}

static void handle_ipc_ai_human_detection()
{
    ipc_debug("GOT AI_HUMAN_DETECTION\n");
    call_callback(IPC_MSG_AI_HUMAN_DETECTION);
}

static void handle_ipc_ai_vehicle_detection()
{
    ipc_debug("GOT AI_VEHICLE_DETECTION\n");
    call_callback(IPC_MSG_AI_VEHICLE_DETECTION);
}

static void handle_ipc_ai_animal_detection()
{
    ipc_debug("GOT AI_ANIMAL_DETECTION\n");
    call_callback(IPC_MSG_AI_ANIMAL_DETECTION);
}

static void handle_ipc_baby_crying()
{
    ipc_debug("GOT BABY CRYING\n");
    call_callback(IPC_MSG_BABY_CRYING);
}

static void handle_ipc_sound_detection()
{
    ipc_debug("GOT SOUND DETECTION\n");
    call_callback(IPC_MSG_SOUND_DETECTION);
}

static void handle_ipc_command(int cmd)
{
    ipc_debug("GOT COMMAND\n");
    call_callback_cmd(cmd);
}

//-----------------------------------------------------------------------------
// GETTERS AND SETTERS
//-----------------------------------------------------------------------------

int ipc_set_callback(IPC_MESSAGE_TYPE type, void (*f)())
{
    if(type>=IPC_MSG_LAST)
        return -1;

    ipc_callbacks[(int)type]=f;

    return 0;
}

//-----------------------------------------------------------------------------
// UTILS
//-----------------------------------------------------------------------------

static void call_callback(IPC_MESSAGE_TYPE type)
{
    func_ptr_t f;
    // Not handling callbacks with parameters (yet)
    f=ipc_callbacks[(int)type];
    if(f!=NULL)
        (*f)(NULL);
}

static void call_callback_cmd(IPC_COMMAND_TYPE type)
{
    func_ptr_t f;
    f=ipc_callbacks[IPC_MSG_COMMAND];
    if(f!=NULL)
        (*f)(&type);
}

static void ipc_debug(const char* fmt, ...)
{
#if IPC_DEBUG
    va_list args;
    va_start (args, fmt);
    vprintf(fmt, args);
    va_end (args);
#endif
}
