#include "mqttv4.h"

/*
 * Just a quick disclaimer.
 * This code is ugly and it is the result of some testing
 * and madness with the MQTT.
 *
 * It will be probably re-written from the ground-up to
 * handle more configurations, messages and callbacks.
 *
 * Warning: No clean exit.
 *
 * Crypto
 */

mqtt_conf_t conf;
mqttv4_conf_t mqttv4_conf;

static void init_mqttv4_config();
static void handle_config(const char *key, const char *value);

files_thread filesThread[3];

int files_delay = 70;        // Wait for xx seconds before search for mp4 files
int files_max_events = 50;   // Number of files reported in the message

extern char *ipc_cmd_params[][2];
int dont_loop = 0;

int gmt;

int get_thread_index(int state)
{
    int i;
    int ret = -1;
    time_t tmpTimeStart;

    time(&tmpTimeStart);
    for (i = 0; i < 3; i++) {
        if (state == filesThread[i].running)
            return i;
    }

    return ret;
}

void *send_files_list(void *arg)
{
    char topic[128];
    mqtt_msg_t msg;
    files_thread *ft = (files_thread *) arg;

    sleep(files_delay);

    fprintf(stderr, "SENDING FILES LIST\n");

    memset(ft->output, '\0', sizeof(ft->output));
    if (getMp4Files(ft->output, gmt, files_max_events, ft->timeStart, ft->timeStop) == 0) {
        msg.msg=ft->output;
        msg.len=strlen(msg.msg);
        msg.topic=topic;

        sprintf(topic, "%s/%s", mqttv4_conf.mqtt_prefix, mqttv4_conf.topic_motion_files);

        mqtt_send_message(&msg, conf.retain_motion_files);
    }
    ft->timeStart = 0;
    ft->timeStop = 0;
    ft->running = TH_AVAILABLE;

    fprintf(stderr, "Thread exiting\n");
    pthread_exit(NULL);
}

void callback_motion_start(void *arg)
{
    char topic[128];
    char cmd[128];
    char bufferFile[L_tmpnam];
    FILE *fImage;
    long int sz;
    char *bufferImage;
    mqtt_msg_t msg;
    int ti;

    fprintf(stderr, "CALLBACK MOTION START\n");

    ti = get_thread_index(TH_AVAILABLE);
    fprintf(stderr, "Thread %d available\n", ti);
    if (ti >= 0 ) {
        time(&filesThread[ti].timeStart);
        filesThread[ti].running = TH_WAITING;
    }

    // Send start message
    msg.msg=mqttv4_conf.motion_start_msg;
    msg.len=strlen(msg.msg);
    msg.topic=topic;

    sprintf(topic, "%s/%s", mqttv4_conf.mqtt_prefix, mqttv4_conf.topic_motion);

    mqtt_send_message(&msg, conf.retain_motion);

    if (strcmp(EMPTY_TOPIC, mqttv4_conf.topic_motion_image) != 0) {
        // Send image
        fprintf(stderr, "Wait %.1f seconds and take a snapshot\n", mqttv4_conf.motion_image_delay);
        tmpnam(bufferFile);
        sprintf(cmd, "%s > %s", MQTTV4_SNAPSHOT, bufferFile);
        usleep((unsigned int) (mqttv4_conf.motion_image_delay * 1000.0 * 1000.0));
        system(cmd);

        fImage = fopen(bufferFile, "r");
        if (fImage == NULL) {
            fprintf(stderr, "Cannot open image file\n");
            remove(bufferFile);
            return;
        }
        fseek(fImage, 0L, SEEK_END);
        sz = ftell(fImage);
        fseek(fImage, 0L, SEEK_SET);

        bufferImage = (char *) malloc(sz * sizeof(char));
        if (bufferImage == NULL) {
            fprintf(stderr, "Cannot allocate memory\n");
            fclose(fImage);
            remove(bufferFile);
            return;
        }
        if (fread(bufferImage, 1, sz, fImage) != sz) {
            fprintf(stderr, "Cannot read image file\n");
            free(bufferImage);
            fclose(fImage);
            remove(bufferFile);
            return;
        }

        msg.msg=bufferImage;
        msg.len=sz;
        msg.topic=topic;

        sprintf(topic, "%s/%s", mqttv4_conf.mqtt_prefix, mqttv4_conf.topic_motion_image);

        mqtt_send_message(&msg, conf.retain_motion_image);

        // Clean
        free(bufferImage);
        fclose(fImage);
        remove(bufferFile);
    }
}

void callback_motion_stop(void *arg)
{
    char topic[128];
    mqtt_msg_t msg;
    int ti;
    time_t tmpTimeStop;

    fprintf(stderr, "CALLBACK MOTION STOP\n");

    time(&tmpTimeStop);

    msg.msg=mqttv4_conf.motion_stop_msg;
    msg.len=strlen(msg.msg);
    msg.topic=topic;

    sprintf(topic, "%s/%s", mqttv4_conf.mqtt_prefix, mqttv4_conf.topic_motion);

    mqtt_send_message(&msg, conf.retain_motion);

    ti = get_thread_index(TH_WAITING);
    fprintf(stderr, "Thread %d waiting\n", ti);
    if (ti >= 0 ) {
        if (filesThread[ti].timeStart != 0) {
            filesThread[ti].timeStop = tmpTimeStop;
            filesThread[ti].running = TH_RUNNING;

            fprintf(stderr, "Thread %d starting\n", ti);
            if (pthread_create(&filesThread[ti].thread, NULL, send_files_list, (void *) &filesThread[ti])) {
                filesThread[ti].timeStart = 0;
                filesThread[ti].timeStop = 0;
                filesThread[ti].running = TH_AVAILABLE;
                fprintf(stderr, "An error occured creating thread\n");
            }
            pthread_detach(filesThread[ti].thread);
        } else {
            filesThread[ti].timeStart = 0;
            filesThread[ti].timeStop = 0;
            filesThread[ti].running = TH_AVAILABLE;
        }
    }
}

void callback_ai_human_detection(void *arg)
{
    char topic[128];
    char cmd[128];
    char bufferFile[L_tmpnam];
    FILE *fImage;
    long int sz;
    char *bufferImage;
    mqtt_msg_t msg;
    int ti;

    fprintf(stderr, "CALLBACK AI_HUMAN_DETECTION\n");

    ti = get_thread_index(TH_AVAILABLE);
    fprintf(stderr, "Thread %d available\n", ti);
    if (ti >= 0 ) {
        time(&filesThread[ti].timeStart);
        filesThread[ti].running = TH_WAITING;
    }

    // Send start message
    msg.msg=mqttv4_conf.ai_human_detection_msg;
    msg.len=strlen(msg.msg);
    msg.topic=topic;

    sprintf(topic, "%s/%s", mqttv4_conf.mqtt_prefix, mqttv4_conf.topic_motion);

    mqtt_send_message(&msg, conf.retain_motion);

    if (strcmp(EMPTY_TOPIC, mqttv4_conf.topic_motion_image) != 0) {
        // Send image
        fprintf(stderr, "Wait %.1f seconds and take a snapshot\n", mqttv4_conf.motion_image_delay);
        tmpnam(bufferFile);
        sprintf(cmd, "%s > %s", MQTTV4_SNAPSHOT, bufferFile);
        usleep((unsigned int) (mqttv4_conf.motion_image_delay * 1000.0 * 1000.0));
        system(cmd);

        fImage = fopen(bufferFile, "r");
        if (fImage == NULL) {
            fprintf(stderr, "Cannot open image file\n");
            remove(bufferFile);
            return;
        }
        fseek(fImage, 0L, SEEK_END);
        sz = ftell(fImage);
        fseek(fImage, 0L, SEEK_SET);

        bufferImage = (char *) malloc(sz * sizeof(char));
        if (bufferImage == NULL) {
            fprintf(stderr, "Cannot allocate memory\n");
            fclose(fImage);
            remove(bufferFile);
            return;
        }
        if (fread(bufferImage, 1, sz, fImage) != sz) {
            fprintf(stderr, "Cannot read image file\n");
            free(bufferImage);
            fclose(fImage);
            remove(bufferFile);
            return;
        }

        msg.msg=bufferImage;
        msg.len=sz;
        msg.topic=topic;

        sprintf(topic, "%s/%s", mqttv4_conf.mqtt_prefix, mqttv4_conf.topic_motion_image);

        mqtt_send_message(&msg, conf.retain_motion_image);

        // Clean
        free(bufferImage);
        fclose(fImage);
        remove(bufferFile);
    }
}

void callback_ai_vehicle_detection(void *arg)
{
    char topic[128];
    char cmd[128];
    char bufferFile[L_tmpnam];
    FILE *fImage;
    long int sz;
    char *bufferImage;
    mqtt_msg_t msg;
    int ti;

    fprintf(stderr, "CALLBACK AI_VEHICLE_DETECTION\n");

    ti = get_thread_index(TH_AVAILABLE);
    fprintf(stderr, "Thread %d available\n", ti);
    if (ti >= 0 ) {
        time(&filesThread[ti].timeStart);
        filesThread[ti].running = TH_WAITING;
    }

    // Send start message
    msg.msg=mqttv4_conf.ai_vehicle_detection_msg;
    msg.len=strlen(msg.msg);
    msg.topic=topic;

    sprintf(topic, "%s/%s", mqttv4_conf.mqtt_prefix, mqttv4_conf.topic_motion);

    mqtt_send_message(&msg, conf.retain_motion);

    if (strcmp(EMPTY_TOPIC, mqttv4_conf.topic_motion_image) != 0) {
        // Send image
        fprintf(stderr, "Wait %.1f seconds and take a snapshot\n", mqttv4_conf.motion_image_delay);
        tmpnam(bufferFile);
        sprintf(cmd, "%s > %s", MQTTV4_SNAPSHOT, bufferFile);
        usleep((unsigned int) (mqttv4_conf.motion_image_delay * 1000.0 * 1000.0));
        system(cmd);

        fImage = fopen(bufferFile, "r");
        if (fImage == NULL) {
            fprintf(stderr, "Cannot open image file\n");
            remove(bufferFile);
            return;
        }
        fseek(fImage, 0L, SEEK_END);
        sz = ftell(fImage);
        fseek(fImage, 0L, SEEK_SET);

        bufferImage = (char *) malloc(sz * sizeof(char));
        if (bufferImage == NULL) {
            fprintf(stderr, "Cannot allocate memory\n");
            fclose(fImage);
            remove(bufferFile);
            return;
        }
        if (fread(bufferImage, 1, sz, fImage) != sz) {
            fprintf(stderr, "Cannot read image file\n");
            free(bufferImage);
            fclose(fImage);
            remove(bufferFile);
            return;
        }

        msg.msg=bufferImage;
        msg.len=sz;
        msg.topic=topic;

        sprintf(topic, "%s/%s", mqttv4_conf.mqtt_prefix, mqttv4_conf.topic_motion_image);

        mqtt_send_message(&msg, conf.retain_motion_image);

        // Clean
        free(bufferImage);
        fclose(fImage);
        remove(bufferFile);
    }
}

void callback_ai_animal_detection(void *arg)
{
    char topic[128];
    char cmd[128];
    char bufferFile[L_tmpnam];
    FILE *fImage;
    long int sz;
    char *bufferImage;
    mqtt_msg_t msg;
    int ti;

    fprintf(stderr, "CALLBACK AI_ANIMAL_DETECTION\n");

    ti = get_thread_index(TH_AVAILABLE);
    fprintf(stderr, "Thread %d available\n", ti);
    if (ti >= 0 ) {
        time(&filesThread[ti].timeStart);
        filesThread[ti].running = TH_WAITING;
    }

    // Send start message
    msg.msg=mqttv4_conf.ai_animal_detection_msg;
    msg.len=strlen(msg.msg);
    msg.topic=topic;

    sprintf(topic, "%s/%s", mqttv4_conf.mqtt_prefix, mqttv4_conf.topic_motion);

    mqtt_send_message(&msg, conf.retain_motion);

    if (strcmp(EMPTY_TOPIC, mqttv4_conf.topic_motion_image) != 0) {
        // Send image
        fprintf(stderr, "Wait %.1f seconds and take a snapshot\n", mqttv4_conf.motion_image_delay);
        tmpnam(bufferFile);
        sprintf(cmd, "%s > %s", MQTTV4_SNAPSHOT, bufferFile);
        usleep((unsigned int) (mqttv4_conf.motion_image_delay * 1000.0 * 1000.0));
        system(cmd);

        fImage = fopen(bufferFile, "r");
        if (fImage == NULL) {
            fprintf(stderr, "Cannot open image file\n");
            remove(bufferFile);
            return;
        }
        fseek(fImage, 0L, SEEK_END);
        sz = ftell(fImage);
        fseek(fImage, 0L, SEEK_SET);

        bufferImage = (char *) malloc(sz * sizeof(char));
        if (bufferImage == NULL) {
            fprintf(stderr, "Cannot allocate memory\n");
            fclose(fImage);
            remove(bufferFile);
            return;
        }
        if (fread(bufferImage, 1, sz, fImage) != sz) {
            fprintf(stderr, "Cannot read image file\n");
            free(bufferImage);
            fclose(fImage);
            remove(bufferFile);
            return;
        }

        msg.msg=bufferImage;
        msg.len=sz;
        msg.topic=topic;

        sprintf(topic, "%s/%s", mqttv4_conf.mqtt_prefix, mqttv4_conf.topic_motion_image);

        mqtt_send_message(&msg, conf.retain_motion_image);

        // Clean
        free(bufferImage);
        fclose(fImage);
        remove(bufferFile);
    }
}

void callback_baby_crying(void *arg)
{
    char topic[128];
    char cmd[128];
    char bufferFile[L_tmpnam];
    FILE *fImage;
    long int sz;
    char *bufferImage;
    mqtt_msg_t msg;
    int ti;

    fprintf(stderr, "CALLBACK BABY CRYING\n");

    ti = get_thread_index(TH_AVAILABLE);
    fprintf(stderr, "Thread %d available\n", ti);
    if (ti >= 0 ) {
        time(&filesThread[ti].timeStart);
        filesThread[ti].running = TH_WAITING;
    }

    // Send message
    msg.msg=mqttv4_conf.baby_crying_msg;
    msg.len=strlen(msg.msg);
    msg.topic=topic;

    sprintf(topic, "%s/%s", mqttv4_conf.mqtt_prefix, mqttv4_conf.topic_motion);

    mqtt_send_message(&msg, conf.retain_motion);

    if (strcmp(EMPTY_TOPIC, mqttv4_conf.topic_motion_image) != 0) {
        // Send image
        fprintf(stderr, "Wait %.1f seconds and take a snapshot\n", mqttv4_conf.motion_image_delay);
        tmpnam(bufferFile);
        sprintf(cmd, "%s > %s", MQTTV4_SNAPSHOT, bufferFile);
        usleep((unsigned int) (mqttv4_conf.motion_image_delay * 1000.0 * 1000.0));
        system(cmd);

        fImage = fopen(bufferFile, "r");
        if (fImage == NULL) {
            fprintf(stderr, "Cannot open image file\n");
            remove(bufferFile);
            return;
        }
        fseek(fImage, 0L, SEEK_END);
        sz = ftell(fImage);
        fseek(fImage, 0L, SEEK_SET);

        bufferImage = (char *) malloc(sz * sizeof(char));
        if (bufferImage == NULL) {
            fprintf(stderr, "Cannot allocate memory\n");
            fclose(fImage);
            remove(bufferFile);
            return;
        }
        if (fread(bufferImage, 1, sz, fImage) != sz) {
            fprintf(stderr, "Cannot read image file\n");
            free(bufferImage);
            fclose(fImage);
            remove(bufferFile);
            return;
        }

        msg.msg=bufferImage;
        msg.len=sz;
        msg.topic=topic;

        sprintf(topic, "%s/%s", mqttv4_conf.mqtt_prefix, mqttv4_conf.topic_motion_image);

        mqtt_send_message(&msg, conf.retain_motion_image);

        // Clean
        free(bufferImage);
        fclose(fImage);
        remove(bufferFile);
    }
}

void callback_sound_detection(void *arg)
{
    char topic[128];
    mqtt_msg_t msg;

    fprintf(stderr, "CALLBACK SOUND DETECTION\n");

    msg.msg=mqttv4_conf.sound_detection_msg;
    msg.len=strlen(msg.msg);
    msg.topic=topic;

    sprintf(topic, "%s/%s", mqttv4_conf.mqtt_prefix, mqttv4_conf.topic_sound_detection);

    mqtt_send_message(&msg, conf.retain_sound_detection);
}

void callback_command(void *arg)
{
    char topic[128];
    char *key, *value;
    mqtt_msg_t msg;
    IPC_COMMAND_TYPE *cmd_type = (IPC_COMMAND_TYPE *) arg;
    int i;

    fprintf(stderr, "CALLBACK COMMAND\n");

    key = ipc_cmd_params[*cmd_type][0];
    value = ipc_cmd_params[*cmd_type][1];

    // Update .conf file
    fprintf(stderr, "Updating file \"%s\", parameter \"%s\" with value \"%s\"\n", CAMERA_CONF_FILE, key, value);
    if (config_replace(CAMERA_CONF_FILE, key, value) != 0) {
        fprintf(stderr, "Error updating file \"%s\", parameter \"%s\" with value \"%s\"\n", CAMERA_CONF_FILE, key, value);
    }

    // Send stat message
    msg.msg=value;
    msg.len=strlen(msg.msg);
    msg.topic=topic;

    sprintf(topic, "%s/camera/%s", mqttv4_conf.mqtt_prefix_stat, key);

    mqtt_send_message(&msg, 1);

    if (dont_loop > 0) return;

    if ((strcasecmp("motion_detection", key) == 0) && (strcasecmp("yes", value) == 0)) {
        // Disable all AI detections
        dont_loop = 1;
        i = (int) IPC_CMD_AI_HUMAN_DETECTION_OFF;
        callback_command(&i);
        i = (int) IPC_CMD_AI_VEHICLE_DETECTION_OFF;
        callback_command(&i);
        i = (int) IPC_CMD_AI_ANIMAL_DETECTION_OFF;
        callback_command(&i);
        dont_loop = 0;
    } else if (((strcasecmp("ai_human_detection", key) == 0) ||
            (strcasecmp("ai_vehicle_detection", key) == 0) ||
            (strcasecmp("ai_animal_detection", key) == 0)) &&
            (strcasecmp("yes", value) == 0)) {

        // Disable motion detection
        dont_loop = 1;
        i = (int) IPC_CMD_AI_MOTION_DETECTION_OFF;
        callback_command(&i);
        dont_loop = 0;
    }
}

int main(int argc, char **argv)
{
    int ret;

    if (argc == 1) {
        gmt = 1;
    } else if (argc == 3) {
        if ((strcmp("-t", argv[1]) == 0) || (strcmp("--time", argv[1]) == 0)) {
            if (strcmp("gmt", argv[2]) == 0) {
                gmt = 1;
            } else if (strcmp("local", argv[2]) == 0) {
                gmt = 0;
            } else {
                printf("Wrong arguments\n");
                exit(EXIT_FAILURE);
            }
        } else {
            printf("Wrong arguments\n");
            exit(EXIT_FAILURE);
        }
    } else {
        printf("Wrong arguments\n");
        exit(EXIT_FAILURE);
    }

    setbuf(stdout, NULL);
    setbuf(stderr, NULL);

    fprintf(stderr, "Starting mqttv4 v%s\n", MQTTV4_VERSION);

    // Init threads struct
    filesThread[0].running = TH_AVAILABLE;
    filesThread[1].running = TH_AVAILABLE;
    filesThread[2].running = TH_AVAILABLE;
    filesThread[0].timeStart = 0;
    filesThread[1].timeStart = 0;
    filesThread[2].timeStart = 0;
    filesThread[0].timeStop = 0;
    filesThread[1].timeStop = 0;
    filesThread[2].timeStop = 0;

    mqtt_init_conf(&conf);
    init_mqttv4_config();
    mqtt_set_conf(&conf);

    if (conf.enable == 1) {
        ret=init_mqtt();
        if(ret!=0)
            exit(EXIT_FAILURE);

        ret=mqtt_connect();
        if(ret!=0)
            exit(EXIT_FAILURE);
    }

    ret=ipc_init();
    if(ret!=0)
        exit(EXIT_FAILURE);

    ipc_set_callback(IPC_MSG_MOTION_START, &callback_motion_start);
    ipc_set_callback(IPC_MSG_MOTION_STOP, &callback_motion_stop);
    ipc_set_callback(IPC_MSG_AI_HUMAN_DETECTION, &callback_ai_human_detection);
    ipc_set_callback(IPC_MSG_AI_VEHICLE_DETECTION, &callback_ai_vehicle_detection);
    ipc_set_callback(IPC_MSG_AI_ANIMAL_DETECTION, &callback_ai_animal_detection);
    ipc_set_callback(IPC_MSG_BABY_CRYING, &callback_baby_crying);
    ipc_set_callback(IPC_MSG_SOUND_DETECTION, &callback_sound_detection);
    ipc_set_callback(IPC_MSG_COMMAND, &callback_command);

    while(1)
    {
        if (conf.enable == 1) {
            mqtt_check_connection();
            mqtt_loop();
        }
        usleep(500*1000);
    }

    ipc_stop();
    if (conf.enable == 1) {
        stop_mqtt();
    }

    return 0;
}

static void handle_config(const char *key, const char *value)
{
    int nvalue;

    // Ok, the configuration handling is UGLY, unsafe and repetitive.
    // It should be fixed in the future by writing a better config
    // handler or by just using a library.

    // If you think to have a better implementation.. PRs are welcome!

    if(strcmp(key, "MQTT")==0)
    {
        if (strcasecmp("yes", value) == 0)
            conf.enable = 1;
        else
            conf.enable = 0;
    }
    else if(strcmp(key, "MQTT_IP")==0)
    {
        strcpy(conf.host, value);
    }
    else if(strcmp(key, "MQTT_CLIENT_ID")==0)
    {
        strcpy(conf.client_id, value);
    }
    else if(strcmp(key, "MQTT_USER")==0)
    {
        conf.user=malloc((char)strlen(value)+1);
        strcpy(conf.user, value);
    }
    else if(strcmp(key, "MQTT_PASSWORD")==0)
    {
        conf.password=malloc((char)strlen(value)+1);
        strcpy(conf.password, value);
    }
    else if(strcmp(key, "MQTT_PORT")==0)
    {
        errno=0;
        nvalue=strtol(value, NULL, 10);
        if(errno==0)
            conf.port=nvalue;
    }
    else if(strcmp(key, "MQTT_KEEPALIVE")==0)
    {
        errno=0;
        nvalue=strtol(value, NULL, 10);
        if(errno==0)
            conf.keepalive=nvalue;
    }
    else if(strcmp(key, "MQTT_QOS")==0)
    {
        errno=0;
        nvalue=strtol(value, NULL, 10);
        if(errno==0)
            conf.qos=nvalue;
    }
    else if(strcmp(key, "MQTT_RETAIN_BIRTH_WILL")==0)
    {
        errno=0;
        nvalue=strtol(value, NULL, 10);
        if(errno==0)
            conf.retain_birth_will=nvalue;
    }
    else if(strcmp(key, "MQTT_RETAIN_MOTION")==0)
    {
        errno=0;
        nvalue=strtol(value, NULL, 10);
        if(errno==0)
            conf.retain_motion=nvalue;
    }
    else if(strcmp(key, "MQTT_RETAIN_MOTION_IMAGE")==0)
    {
        errno=0;
        nvalue=strtol(value, NULL, 10);
        if(errno==0)
            conf.retain_motion_image=nvalue;
    }
    else if(strcmp(key, "MQTT_RETAIN_MOTION_FILES")==0)
    {
        errno=0;
        nvalue=strtol(value, NULL, 10);
        if(errno==0)
            conf.retain_motion_files=nvalue;
    }
    else if(strcmp(key, "MQTT_RETAIN_SOUND_DETECTION")==0)
    {
        errno=0;
        nvalue=strtol(value, NULL, 10);
        if(errno==0)
            conf.retain_sound_detection=nvalue;
    }
    else if(strcmp(key, "MQTT_PREFIX")==0)
    {
        conf.mqtt_prefix=malloc((char)strlen(value)+1);
        strcpy(conf.mqtt_prefix, value);
        mqttv4_conf.mqtt_prefix=malloc((char)strlen(value)+1);
        strcpy(mqttv4_conf.mqtt_prefix, value);

        mqttv4_conf.mqtt_prefix_stat=malloc((char)strlen(value)+1+5);
        sprintf(mqttv4_conf.mqtt_prefix_stat, "%s/stat", value);
    }
    else if(strcmp(key, "TOPIC_BIRTH_WILL")==0)
    {
        conf.topic_birth_will=malloc((char)strlen(value)+1);
        strcpy(conf.topic_birth_will, value);
        mqttv4_conf.topic_birth_will=malloc((char)strlen(value)+1);
        strcpy(mqttv4_conf.topic_birth_will, value);
    }
    else if(strcmp(key, "TOPIC_MOTION")==0)
    {
        mqttv4_conf.topic_motion=malloc((char)strlen(value)+1);
        strcpy(mqttv4_conf.topic_motion, value);
    }
    else if(strcmp(key, "TOPIC_MOTION_IMAGE")==0)
    {
        mqttv4_conf.topic_motion_image=malloc((char)strlen(value)+1);
        strcpy(mqttv4_conf.topic_motion_image, value);
    }
    else if(strcmp(key, "MOTION_IMAGE_DELAY")==0)
    {
        mqttv4_conf.motion_image_delay=strtod(value, NULL);
    }
    else if(strcmp(key, "TOPIC_MOTION_FILES")==0)
    {
        mqttv4_conf.topic_motion_files=malloc((char)strlen(value)+1);
        strcpy(mqttv4_conf.topic_motion_files, value);
    }
    else if(strcmp(key, "TOPIC_SOUND_DETECTION")==0)
    {
        mqttv4_conf.topic_sound_detection=malloc((char)strlen(value)+1);
        strcpy(mqttv4_conf.topic_sound_detection, value);
    }
    else if(strcmp(key, "BIRTH_MSG")==0)
    {
        conf.birth_msg=malloc((char)strlen(value)+1);
        strcpy(conf.birth_msg, value);
        mqttv4_conf.birth_msg=malloc((char)strlen(value)+1);
        strcpy(mqttv4_conf.birth_msg, value);
    }
    else if(strcmp(key, "WILL_MSG")==0)
    {
        conf.will_msg=malloc((char)strlen(value)+1);
        strcpy(conf.will_msg, value);
        mqttv4_conf.will_msg=malloc((char)strlen(value)+1);
        strcpy(mqttv4_conf.will_msg, value);
    }
    else if(strcmp(key, "MOTION_START_MSG")==0)
    {
        mqttv4_conf.motion_start_msg=malloc((char)strlen(value)+1);
        strcpy(mqttv4_conf.motion_start_msg, value);
    }
    else if(strcmp(key, "MOTION_STOP_MSG")==0)
    {
        mqttv4_conf.motion_stop_msg=malloc((char)strlen(value)+1);
        strcpy(mqttv4_conf.motion_stop_msg, value);
    }
    else if(strcmp(key, "AI_HUMAN_DETECTION_MSG")==0)
    {
        mqttv4_conf.ai_human_detection_msg=malloc((char)strlen(value)+1);
        strcpy(mqttv4_conf.ai_human_detection_msg, value);
    }
    else if(strcmp(key, "AI_VEHICLE_DETECTION_MSG")==0)
    {
        mqttv4_conf.ai_vehicle_detection_msg=malloc((char)strlen(value)+1);
        strcpy(mqttv4_conf.ai_vehicle_detection_msg, value);
    }
    else if(strcmp(key, "AI_ANIMAL_DETECTION_MSG")==0)
    {
        mqttv4_conf.ai_animal_detection_msg=malloc((char)strlen(value)+1);
        strcpy(mqttv4_conf.ai_animal_detection_msg, value);
    }
    else if(strcmp(key, "BABY_CRYING_MSG")==0)
    {
        mqttv4_conf.baby_crying_msg=malloc((char)strlen(value)+1);
        strcpy(mqttv4_conf.baby_crying_msg, value);
    }
    else if(strcmp(key, "SOUND_DETECTION_MSG")==0)
    {
        mqttv4_conf.sound_detection_msg=malloc((char)strlen(value)+1);
        strcpy(mqttv4_conf.sound_detection_msg, value);
    }
    else
    {
        fprintf(stderr, "key: %s | value: %s\n", key, value);
        fprintf(stderr, "Unrecognized config line, ignore it\n");
    }
}

static void init_mqttv4_config()
{
    // Setting conf vars to NULL
    mqttv4_conf.mqtt_prefix=NULL;
    mqttv4_conf.topic_birth_will=NULL;
    mqttv4_conf.topic_motion=NULL;
    mqttv4_conf.topic_motion_image=NULL;
    mqttv4_conf.motion_image_delay=0.5;
    mqttv4_conf.topic_motion_files=NULL;
    mqttv4_conf.topic_sound_detection=NULL;
    mqttv4_conf.birth_msg=NULL;
    mqttv4_conf.will_msg=NULL;
    mqttv4_conf.motion_start_msg=NULL;
    mqttv4_conf.motion_stop_msg=NULL;
    mqttv4_conf.ai_human_detection_msg=NULL;
    mqttv4_conf.ai_vehicle_detection_msg=NULL;
    mqttv4_conf.ai_animal_detection_msg=NULL;
    mqttv4_conf.baby_crying_msg=NULL;
    mqttv4_conf.sound_detection_msg=NULL;

    if(init_config(SYSTEM_CONF_FILE)!=0)
    {
        fprintf(stderr, "Cannot open config file. Skipping.\n");
        return;
    }

    config_set_handler(&handle_config);
    config_parse();
    stop_config();

    if(init_config(MQTTV4_CONF_FILE)!=0)
    {
        fprintf(stderr, "Cannot open config file. Skipping.\n");
        return;
    }

    config_set_handler(&handle_config);
    config_parse();
    stop_config();

    // Setting default for all char* vars
    if(conf.mqtt_prefix == NULL)
    {
        conf.mqtt_prefix=malloc((char)strlen("yicam")+1);
        strcpy(conf.mqtt_prefix, "yicam");
    }
    if(mqttv4_conf.mqtt_prefix == NULL)
    {
        mqttv4_conf.mqtt_prefix=malloc((char)strlen("yicam")+1);
        strcpy(mqttv4_conf.mqtt_prefix, "yicam");
        mqttv4_conf.mqtt_prefix_stat=malloc((char)strlen("yicam/stat")+1);
        strcpy(mqttv4_conf.mqtt_prefix_stat, "yicam/stat");
    }
    if(conf.topic_birth_will == NULL)
    {
        conf.topic_birth_will=malloc((char)strlen(EMPTY_TOPIC)+1);
        strcpy(conf.topic_birth_will, EMPTY_TOPIC);
    }
    if(mqttv4_conf.topic_birth_will == NULL)
    {
        mqttv4_conf.topic_birth_will=malloc((char)strlen(EMPTY_TOPIC)+1);
        strcpy(mqttv4_conf.topic_birth_will, EMPTY_TOPIC);
    }
    if(mqttv4_conf.topic_motion == NULL)
    {
        mqttv4_conf.topic_motion=malloc((char)strlen(EMPTY_TOPIC)+1);
        strcpy(mqttv4_conf.topic_motion, EMPTY_TOPIC);
    }
    if(mqttv4_conf.topic_motion_image == NULL)
    {
        mqttv4_conf.topic_motion_image=malloc((char)strlen(EMPTY_TOPIC)+1);
        strcpy(mqttv4_conf.topic_motion_image, EMPTY_TOPIC);
    }
    if(mqttv4_conf.topic_motion_files == NULL)
    {
        mqttv4_conf.topic_motion_files=malloc((char)strlen(EMPTY_TOPIC)+1);
        strcpy(mqttv4_conf.topic_motion_files, EMPTY_TOPIC);
    }
    if(mqttv4_conf.topic_sound_detection == NULL)
    {
        mqttv4_conf.topic_sound_detection=malloc((char)strlen(EMPTY_TOPIC)+1);
        strcpy(mqttv4_conf.topic_sound_detection, EMPTY_TOPIC);
    }
    if(conf.birth_msg == NULL)
    {
        conf.birth_msg=malloc((char)strlen("online")+1);
        strcpy(conf.birth_msg, "online");
    }
    if(mqttv4_conf.birth_msg == NULL)
    {
        mqttv4_conf.birth_msg=malloc((char)strlen("online")+1);
        strcpy(mqttv4_conf.birth_msg, "online");
    }
    if(conf.will_msg == NULL)
    {
        conf.will_msg=malloc((char)strlen("offline")+1);
        strcpy(conf.will_msg, "offline");
    }
    if(mqttv4_conf.will_msg == NULL)
    {
        mqttv4_conf.will_msg=malloc((char)strlen("offline")+1);
        strcpy(mqttv4_conf.will_msg, "offline");
    }
    if(mqttv4_conf.motion_start_msg == NULL)
    {
        mqttv4_conf.motion_start_msg=malloc((char)strlen("motion_start")+1);
        strcpy(mqttv4_conf.motion_start_msg, "motion_start");
    }
    if(mqttv4_conf.motion_stop_msg == NULL)
    {
        mqttv4_conf.motion_stop_msg=malloc((char)strlen("motion_stop")+1);
        strcpy(mqttv4_conf.motion_stop_msg, "motion_stop");
    }
    if(mqttv4_conf.ai_human_detection_msg == NULL)
    {
        mqttv4_conf.ai_human_detection_msg=malloc((char)strlen("human")+1);
        strcpy(mqttv4_conf.ai_human_detection_msg, "human");
    }
    if(mqttv4_conf.ai_vehicle_detection_msg == NULL)
    {
        mqttv4_conf.ai_vehicle_detection_msg=malloc((char)strlen("vehicle")+1);
        strcpy(mqttv4_conf.ai_vehicle_detection_msg, "vehicle");
    }
    if(mqttv4_conf.ai_animal_detection_msg == NULL)
    {
        mqttv4_conf.ai_animal_detection_msg=malloc((char)strlen("animal")+1);
        strcpy(mqttv4_conf.ai_animal_detection_msg, "animal");
    }
    if(mqttv4_conf.baby_crying_msg == NULL)
    {
        mqttv4_conf.baby_crying_msg=malloc((char)strlen("crying")+1);
        strcpy(mqttv4_conf.baby_crying_msg, "crying");
    }
    if(mqttv4_conf.sound_detection_msg == NULL)
    {
        mqttv4_conf.sound_detection_msg=malloc((char)strlen("sound")+1);
        strcpy(mqttv4_conf.sound_detection_msg, "sound");
    }
}
