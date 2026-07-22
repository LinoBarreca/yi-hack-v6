#!/bin/sh

# 6.0.1


. /home/yi-hack/www/cgi-bin/validate.sh

if ! validateQueryString "$QUERY_STRING"; then
    printf "Content-type: application/json\r\n\r\n"
    printf "{\n"
    printf "\"%s\":\"%s\"\\n" "error" "true"
    printf "}"
    exit
fi

# First key=value pair, split with parameter expansion (no echo|cut forks).
PAIR=${QUERY_STRING%%\&*}
PARAM=${PAIR%%=*}
VALUE=${PAIR#*=}

TEST_WITH_PROXY="0"
if [ "$PARAM" == "proxy" ]; then
    if [ "$VALUE" == "1" ]; then
        TEST_WITH_PROXY="1"
    fi
else
    printf "Content-type: application/json\r\n\r\n"
    printf "{\n"
    printf "\"%s\":\"%s\"\\n" "error" "true"
    printf "}"
    exit
fi

if [ "$TEST_WITH_PROXY" == "1" ]; then
    RES=$(IFS='' proxychains4 wget -O- -q http://ipinfo.io)
else
    RES=$(IFS='' wget -O- -q http://ipinfo.io)
fi

printf "Content-type: application/json\r\n\r\n"
printf "{\n"
printf "\"%s\":\"%s\",\\n" "error" "false"
printf "\"%s\":%s\\n" "result" "$RES"
printf "}"
