#!/bin/bash -eu

while [ -n "${1+x}" ]
do
  rclone --config /root/.config/rclone/rclone.conf move -L "${RCLONE_FLAGS[@]:-}" --transfers=1 --files-from "$2" "$1" "$RCLONE_DRIVE:$RCLONE_PATH" >> "$LOG_FILE" 2>&1
  shift 2
done
