#!/bin/sh

# 6.0.1

DIR="none"
TIME="0.3"

OIFS=$IFS; IFS='&'; set -- $QUERY_STRING; IFS=$OIFS
for KV in "$@"
do
    CONF="${KV%%=*}"
    VAL="${KV#*=}"

    if [ "$CONF" == "dir" ] ; then
        DIR="-m $VAL"
    elif [ "$CONF" == "time" ] ; then
        TIME="$VAL"
    fi
done

if [ "$DIR" != "none" ] ; then
    ipc_cmd $DIR
    sleep $TIME
    ipc_cmd -m stop
fi

printf "Content-type: application/json\r\n\r\n"

printf "{\n"
printf "}"
