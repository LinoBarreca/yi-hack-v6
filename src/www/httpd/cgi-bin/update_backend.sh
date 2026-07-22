#!/bin/sh

# 6.0.1


REMOTE_VERSION_FILE=/tmp/.hackremotever
REMOTE_NEWVERSION_FILE=/tmp/.hacknewver

LOCAL_VERSION_FILE=/home/yi-hack/extra/../version

IS_SD_PRESENT="NO"

if grep -qs '/tmp/sd' /proc/mounts; then
    IS_SD_PRESENT="YES"
fi

printf "Content-type: application/json\r\n\r\n"

printf "{\n"

LOCAL_VERSION="";  read LOCAL_VERSION  < $LOCAL_VERSION_FILE
REMOTE_VERSION=""; read REMOTE_VERSION 2>/dev/null < $REMOTE_VERSION_FILE
NEEDS_UPDATE="";   read NEEDS_UPDATE   2>/dev/null < $REMOTE_NEWVERSION_FILE
printf "\"%s\":\"%s\",\n"  "LOCAL_VERSION" "$LOCAL_VERSION"
printf "\"%s\":\"%s\",\n"  "REMOTE_VERSION" "$REMOTE_VERSION"
printf "\"%s\":\"%s\",\n"  "NEEDS_UPDATE" "$NEEDS_UPDATE"
printf "\"%s\":\"%s\",\n"  "IS_SD_PRESENT" "$IS_SD_PRESENT"

# Empty values to "close" the json
printf "\"%s\":\"%s\"\n"  "NULL" "NULL"

printf "}"
