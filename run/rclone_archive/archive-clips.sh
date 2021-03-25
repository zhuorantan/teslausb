#!/bin/bash -eu

while [ -n "${1+x}" ]
do
  rclone --config /root/.config/rclone/rclone.conf move --transfers=1 --files-from "$2" "$1" "$RCLONE_DRIVE:$RCLONE_PATH" --create-empty-src-dirs --delete-empty-src-dirs >> "$LOG_FILE" 2>&1
  shift 2
done
