#!/bin/sh

# 6.0.1

printf "Content-type: text/javascript\r\n\r\n"

printf "hostname=\"%s\";" $(cat /home/yi-hack/config/hostname)
