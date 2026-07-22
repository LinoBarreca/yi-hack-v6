#!/bin/sh

# 6.0.1

read MODEL_SUFFIX < /home/app/.camver
read FW_VERSION < /home/yi-hack/extra/../version
read BASELINE_VERSION < /home/yi-hack/version

export PATH=/usr/bin:/usr/sbin:/bin:/sbin:/home/base/tools:/home/app/localbin:/home/base:/home/yi-hack/extra/bin:/home/yi-hack/extra/sbin:/home/yi-hack/extra/usr/bin:/home/yi-hack/extra/usr/sbin
export LD_LIBRARY_PATH=/lib:/usr/lib:/home/lib:/home/qigan/lib:/home/app/locallib:/tmp/sd:/tmp/sd/gdb:/home/yi-hack/extra/lib


# gh_fetch <url> <jq filter> - query the GitHub releases API.
#
# wget's stderr is suppressed only to keep its progress meter out of the CGI
# response, but that also made a DNS/TLS/offline failure look exactly like
# "no release found": the pipe into jq discards wget's exit status, leaving an
# empty version string that the callers then treated as a valid answer. Capture
# first, check the rc, and report the real cause to the httpd log.
gh_fetch() {
    _gf_json=$(wget -O - "$1" 2>/dev/null) || {
        echo "fw_upgrade[ERROR]: cannot reach $1 (network/DNS/TLS failure)" >&2
        return 1
    }
    printf '%s' "$_gf_json" | jq -r "$2"
}

NAME="${QUERY_STRING%%=*}"
VAL="${QUERY_STRING#*=}"

if [ "$NAME" != "get" ] ; then
    exit
fi

if [ "$VAL" == "info" ] ; then
    printf "Content-type: application/json\r\n\r\n"

    read FW_VERSION < /home/yi-hack/extra/../version
    LATEST_FW=$(gh_fetch https://api.github.com/repos/LinoBarreca/yi-hack-v6/releases/latest '.tag_name // ""')
    PRERELEASE_FW=$(gh_fetch https://api.github.com/repos/LinoBarreca/yi-hack-v6/releases '[.[] | select(.prerelease)][0].tag_name // ""')
	
    printf "{\n"
    printf "\"%s\":\"%s\",\n" "fw_version"       "$FW_VERSION"
    printf "\"%s\":\"%s\",\n" "latest_fw"       "$LATEST_FW"
    printf "\"%s\":\"%s\"\n" "prerelease_fw"       "$PRERELEASE_FW"
    printf "}"

elif [ "$VAL" == "upgrade" ] ; then
    FREE_SD=$(df /tmp/sd/ | awk '/mmc/{print $4}')
    if [ -z "$FREE_SD" ]; then
        printf "Content-type: text/html\r\n\r\n"
        printf "No SD detected."
        exit
    fi

    if [ $FREE_SD -lt 100000 ]; then
        printf "Content-type: text/html\r\n\r\n"
        printf "No space left on SD."
        exit
    fi

    # Clean old upgrades
    rm -rf /tmp/sd/${MODEL_SUFFIX}
    rm -rf /tmp/sd/${MODEL_SUFFIX}.conf
    rm -rf /tmp/sd/Factory
    rm -rf /tmp/sd/newhome
    rm /tmp/sd/rootfs*
    rm /tmp/sd/home*

    mkdir -p /tmp/sd/${MODEL_SUFFIX}
    mkdir -p /tmp/sd/${MODEL_SUFFIX}.conf
 #   cd /tmp/sd/${MODEL_SUFFIX}
    cd /tmp/sd
    
    if [ -f /tmp/sd/${MODEL_SUFFIX}_x.x.x.tgz ]; then
#        mv /tmp/sd/${MODEL_SUFFIX}_x.x.x.tgz /tmp/sd/${MODEL_SUFFIX}/${MODEL_SUFFIX}_x.x.x.tgz
        LATEST_FW="x.x.x"
    else
        LATEST_FW=$(gh_fetch https://api.github.com/repos/alienatedsec/yi-hack-v6/releases/latest '.tag_name // ""')
        if [ -z "$LATEST_FW" ]; then
            printf "Content-type: text/html\r\n\r\n"
            printf "Cannot reach the update server. Check the network connection."
            exit
        fi
        if [ "$FW_VERSION" == "$LATEST_FW" ]; then
            printf "Content-type: text/html\r\n\r\n"
            printf "No new firmware available."
            exit
        elif [ "$BASELINE_VERSION" != "6.0.1" ]; then
            printf "Content-type: text/html\r\n\r\n"
            printf "Wrong baseline version"
            exit
        fi
        
        wget https://github.com/LinoBarreca/yi-hack-v6/releases/download/$LATEST_FW/${MODEL_SUFFIX}_${LATEST_FW}.tgz
        
        if [ ! -f ${MODEL_SUFFIX}_${LATEST_FW}.tgz ]; then
            printf "Content-type: text/html\r\n\r\n"
            printf "Unable to download firmware file."
            exit
        fi
    fi

    # Backup configuration
    cp -rf /home/yi-hack/config/* /tmp/sd/${MODEL_SUFFIX}.conf/
    rm /tmp/sd/${MODEL_SUFFIX}.conf/*.tar.gz

    # Prepare new hack
    gzip -d ${MODEL_SUFFIX}_${LATEST_FW}.tgz
    tar xvf ${MODEL_SUFFIX}_${LATEST_FW}.tar
    rm ${MODEL_SUFFIX}_${LATEST_FW}.tar
    mkdir -p /tmp/sd/${MODEL_SUFFIX}/yi-hack/etc
    cp -rf /tmp/sd/${MODEL_SUFFIX}.conf/* /tmp/sd/${MODEL_SUFFIX}/yi-hack/etc/

    # Report the status to the caller
    printf "Content-type: text/html\r\n\r\n"
    printf "Download completed, rebooting and upgrading."

    sync
    sync
    sync
    sleep 1
    reboot

elif [ "$VAL" == "preupgrade" ] ; then
    FREE_SD=$(df /tmp/sd/ | awk '/mmc/{print $4}')
    if [ -z "$FREE_SD" ]; then
        printf "Content-type: text/html\r\n\r\n"
        printf "No SD detected."
        exit
    fi

    if [ $FREE_SD -lt 100000 ]; then
        printf "Content-type: text/html\r\n\r\n"
        printf "No space left on SD."
        exit
    fi

    # Clean old upgrades
    rm -rf /tmp/sd/${MODEL_SUFFIX}
    rm -rf /tmp/sd/${MODEL_SUFFIX}.conf
    rm -rf /tmp/sd/Factory
    rm -rf /tmp/sd/newhome
    rm /tmp/sd/rootfs*
    rm /tmp/sd/home*

    mkdir -p /tmp/sd/${MODEL_SUFFIX}
    mkdir -p /tmp/sd/${MODEL_SUFFIX}.conf
 #   cd /tmp/sd/${MODEL_SUFFIX}
    cd /tmp/sd
    
    if [ -f /tmp/sd/${MODEL_SUFFIX}_x.x.x.tgz ]; then
#        mv /tmp/sd/${MODEL_SUFFIX}_x.x.x.tgz /tmp/sd/${MODEL_SUFFIX}/${MODEL_SUFFIX}_x.x.x.tgz
        PRERELEASE_FW="x.x.x"
    else
        PRERELEASE_FW=$(gh_fetch https://api.github.com/repos/alienatedsec/yi-hack-v6/releases '[.[] | select(.prerelease)][0].tag_name // ""')
        if [ -z "$PRERELEASE_FW" ]; then
            printf "Content-type: text/html\r\n\r\n"
            printf "Cannot reach the update server. Check the network connection."
            exit
        fi
        if [ "$FW_VERSION" == "$PRERELEASE_FW" ]; then
            printf "Content-type: text/html\r\n\r\n"
            printf "No new firmware available."
            exit
        elif [ "$BASELINE_VERSION" != "6.0.1" ]; then
            printf "Content-type: text/html\r\n\r\n"
            printf "Wrong baseline version"
            exit
        fi

        wget https://github.com/LinoBarreca/yi-hack-v6/releases/download/$PRERELEASE_FW/${MODEL_SUFFIX}_${PRERELEASE_FW}.tgz
        
        if [ ! -f ${MODEL_SUFFIX}_${PRERELEASE_FW}.tgz ]; then
            printf "Content-type: text/html\r\n\r\n"
            printf "Unable to download firmware file."
            exit
        fi
    fi

    # Backup configuration
    cp -rf /home/yi-hack/config/* /tmp/sd/${MODEL_SUFFIX}.conf/
    rm /tmp/sd/${MODEL_SUFFIX}.conf/*.tar.gz

    # Prepare new hack
    gzip -d ${MODEL_SUFFIX}_${PRERELEASE_FW}.tgz
    tar xvf ${MODEL_SUFFIX}_${PRERELEASE_FW}.tar
    rm ${MODEL_SUFFIX}_${PRERELEASE_FW}.tar
    mkdir -p /tmp/sd/${MODEL_SUFFIX}/yi-hack/etc
    cp -rf /tmp/sd/${MODEL_SUFFIX}.conf/* /tmp/sd/${MODEL_SUFFIX}/yi-hack/etc/

    # Report the status to the caller
    printf "Content-type: text/html\r\n\r\n"
    printf "Download completed, rebooting and upgrading."

    sync
    sync
    sync
    sleep 1
    reboot
fi

