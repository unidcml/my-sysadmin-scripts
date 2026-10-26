#!/bin/bash

INTERVAL=5
LOG_FILE=monitor.log

while true; do
    {
        echo "--- $(date '+%Y-%m-%d %H:%M:%S') ---"
        free -h
        df -h
        uptime
    } >> "$LOG_FILE" || {
        echo "Не удалось записать $LOG_FILE" >&2
        exit 1
    }
    sleep "$INTERVAL"
done
