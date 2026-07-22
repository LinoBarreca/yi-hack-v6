#!/bin/sh

# 6.0.1

printf "Content-type: text/javascript\r\n\r\n"

HN=""; read HN 2>/dev/null < /home/yi-hack/config/hostname
printf "hostname=\"%s\";" "$HN"
