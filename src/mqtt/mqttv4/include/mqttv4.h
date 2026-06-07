#ifndef MQTTV4_H
#define MQTTV4_H

#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "config.h"
#include "ipc.h"
#include "mqtt.h"
#include "files.h"

#define MQTTV4_VERSION      "0.1.0"
#define SYSTEM_CONF_FILE    "/home/yi-hack/config/system.conf"
#define MQTTV4_CONF_FILE    "/home/yi-hack/config/mqttv4.conf"
#define CAMERA_CONF_FILE    "/home/yi-hack/config/camera.conf"

#define MQTTV4_SNAPSHOT     "export MOD=$(cat /home/app/.camver); /home/yi-hack/extra/bin/imggrabber -m $MOD -r low -w"

#define TH_AVAILABLE 0
#define TH_WAITING   1
#define TH_RUNNING   2

typedef struct
{
    char *mqtt_prefix;
    char *mqtt_prefix_stat;
    char *topic_birth_will;
    char *topic_motion;
    char *topic_motion_image;
    double motion_image_delay;
    char *topic_motion_files;
    char *topic_sound_detection;
    char *birth_msg;
    char *will_msg;
    char *motion_start_msg;
    char *motion_stop_msg;
    char *ai_human_detection_msg;
    char *ai_vehicle_detection_msg;
    char *ai_animal_detection_msg;
    char *baby_crying_msg;
    char *sound_detection_msg;
} mqttv4_conf_t;

#endif // MQTTV4_H
