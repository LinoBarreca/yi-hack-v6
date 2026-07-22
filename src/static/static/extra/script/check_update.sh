#!/bin/sh

# 6.0.1



. /home/yi-hack/base/script/get_config.sh

MAX_RETRY=10
N_RETRY=0

REMOTE_RELEASE_URL=https://api.github.com/repos/alienatedsec/yi-hack-v6/releases/latest
REMOTE_RELEASE_FILE=/tmp/.hackremoterel
REMOTE_VERSION_FILE=/tmp/.hackremotever
REMOTE_NEWVERSION_FILE=/tmp/.hacknewver

LOCAL_VERSION_FILE=/home/yi-hack/extra/../version

CHECK_UPDATES=""; load_config system CHECK_UPDATES
if [[ $CHECK_UPDATES == "yes" ]] ; then
    while : ; do
        # Get the latest version number from github
        wget -T 10 -O $REMOTE_RELEASE_FILE $REMOTE_RELEASE_URL --no-check-certificate &> /dev/null

        if [ ! -f $REMOTE_RELEASE_FILE ]; then
            # The remote version number hasn't been downloaded yet (timeout)
            # The camera might be connecting to the wifi
            # Keep checking every 5 seconds and increment retry number
            sleep 5
            ((N_RETRY++))
        fi
        
        [ ! -f $REMOTE_RELEASE_FILE ] && [ $N_RETRY -le $MAX_RETRY ] || break
    done
    
    if [ -f $REMOTE_RELEASE_FILE ] ; then
        jq -r .tag_name < $REMOTE_RELEASE_FILE > $REMOTE_VERSION_FILE
        rm $REMOTE_RELEASE_FILE
        V_LOCAL=$(cut -d'_' -f1 $LOCAL_VERSION_FILE)
        V_REMOTE=$(cut -d'_' -f1 $REMOTE_VERSION_FILE)

        # Split MAJOR.MINOR.PATCH with the shell itself (no cut per component)
        OIFS=$IFS; IFS='.'
        set -- $V_LOCAL;  LOCAL_MAJOR=$1;  LOCAL_MINOR=$2;  LOCAL_PATCH=$3
        set -- $V_REMOTE; REMOTE_MAJOR=$1; REMOTE_MINOR=$2; REMOTE_PATCH=$3
        IFS=$OIFS


        V_LOCAL_NUM=$(printf "%03d%03d%03d" $LOCAL_MAJOR $LOCAL_MINOR $LOCAL_PATCH)
        V_REMOTE_NUM=$(printf "%03d%03d%03d" $REMOTE_MAJOR $REMOTE_MINOR $REMOTE_PATCH)
        
        if [ $V_LOCAL_NUM -lt $V_REMOTE_NUM ] ; then
            echo "yes" > $REMOTE_NEWVERSION_FILE
        elif [ $V_LOCAL_NUM -eq $V_REMOTE_NUM ] ; then
            echo "no" > $REMOTE_NEWVERSION_FILE
        elif [ $V_LOCAL_NUM -gt $V_REMOTE_NUM ] ; then
            echo "no_currentversionisbeta" > $REMOTE_NEWVERSION_FILE
        fi
    fi
fi
