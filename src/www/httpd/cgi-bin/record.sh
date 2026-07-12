#!/bin/sh

# 6.0.1

validateNumber()
{
    RES=$(echo ${1} | sed -E 's/^[0-9]*$//g')
    if [ -z $RES ]; then
        TIME=$1
    else
        TIME="invalid"
    fi
}

TIME=60

OIFS=$IFS; IFS='&'; set -- $QUERY_STRING; IFS=$OIFS
for KV in "$@"
do
    CONF="${KV%%=*}"
    VAL="${KV#*=}"

    if [ "$CONF" == "time" ] ; then
        TIME="$VAL"
    fi
done

validateNumber $TIME

if [ "$TIME" == "invalid" ] ; then
    printf "Content-type: application/json\r\n\r\n"
    printf "{\n"
    printf "\"error\":\"Invalid time\"\n"
    printf "}\n"
    exit
fi

ipc_cmd -S $TIME &

printf "Content-type: application/json\r\n\r\n"
printf "{\n"
printf "}\n"
