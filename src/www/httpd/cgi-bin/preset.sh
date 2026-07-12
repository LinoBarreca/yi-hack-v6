#!/bin/sh

# 6.0.1

PTZ_CONF_FILE=/home/yi-hack/config/ptz_presets.conf
PTZ_SCRIPT=/home/yi-hack/extra/script/ptz_presets.sh

. /home/yi-hack/www/cgi-bin/validate.sh

return_error() {
    printf "Content-type: application/json\r\n\r\n"
    printf "{\n"
    printf "\"%s\":\"%s\",\\n" "error" "true"
    printf "\"%s\":\"%s\"\\n" "message" "$@"
    printf "}"
}

if ! $(validateQueryString $QUERY_STRING); then
    return_error "Invalid query"
    exit
fi

ACTION="none"
NUM=-1
NAME=""

OIFS=$IFS; IFS='&'; set -- $QUERY_STRING; IFS=$OIFS
for KV in "$@"
do
    CONF="${KV%%=*}"
    VAL="${KV#*=}"

    if [ "$CONF" == "action" ] ; then
        ACTION="$VAL"
    elif [ "$CONF" == "num" ] ; then
        if $(validateNumber $VAL); then
            NUM="$VAL"
        else
            if [ "$VAL" == "all" ]; then
                NUM="$VAL"
            else
                return_error "Wrong arguments"
                exit
            fi
        fi
    elif [ "$CONF" == "name" ] ; then
        if $(validateString $VAL); then
            NAME="$VAL"
        else
            return_error "Wrong arguments"
            exit
        fi
    fi
done

if [ "$ACTION" == "none" ] || [ "$ACTION" == "get_presets" ]; then
    return_error -99
    exit
fi

if [ "$NUM" != "-1" ]; then
    NUM="-n $NUM"
else
    NUM=""
fi
if [ ! -z $NAME ]; then
    NAME="-m $NAME"
else
    NAME=""
fi

RES=$($PTZ_SCRIPT -a $ACTION $NUM $NAME)

if [ "$RES" == "" ]; then
    printf "Content-type: application/json\r\n\r\n"
    printf "{\n"
    printf "\"%s\":\"%s\"\\n" "error" "false"
    printf "}"
else
    return_error $RES
fi
