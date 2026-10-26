#!/bin/bash

INTERVAL=5
LOG_FILE=monitor.log

while true; do
    {
        echo "--- $(date '+%Y-%m-%d %H:%M:%S') ---"
        free -h
        df -h
        uptime
    } >> "$LOG_FILE"
    sleep "$INTERVAL"
done
