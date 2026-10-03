#!/bin/bash

set -Eeuo pipefail

port="${SERVER_PORT:-7777}"
pid_file="${APP_PID_FILE:-/tmp/container/app.pid}"

if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
    exit 1
fi

test -s "$pid_file"
pid="$(cat "$pid_file")"
kill -0 "$pid" 2>/dev/null

exec 3<>"/dev/udp/127.0.0.1/$port"
{
    printf '\x01'
    head -c 27 /dev/zero
    printf '\x08'
} >&3

IFS= read -r -n 1 -t 5 <&3
