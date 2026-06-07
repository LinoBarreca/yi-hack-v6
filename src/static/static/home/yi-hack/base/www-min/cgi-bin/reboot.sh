#!/bin/sh
printf "Content-type: application/json\r\n\r\n"
printf '{"error":"false"}'
sync
(sleep 1; reboot) &
