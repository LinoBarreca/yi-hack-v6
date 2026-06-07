#ifndef FILES_H
#define FILES_H

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <dirent.h>
#include <unistd.h>
#include <sys/stat.h>
#include <pthread.h>

#define RECORD_PATH "/tmp/sd/record"

typedef struct {
    pthread_t thread;
    time_t timeStart;
    time_t timeStop;
    char output[2048];   // Enough for 50 files
    int running;
} files_thread;

int getMp4Files(char *output, int gmt, int limit, time_t startTime, time_t endTime);

#endif // FILES_H
