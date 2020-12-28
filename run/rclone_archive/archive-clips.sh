#!/bin/bash -eu

source /root/.teslaCamRcloneConfig

while [ -n "${1+x}" ]
do
  # shellcheck disable=SC2154
  rclone --config /root/.config/rclone/rclone.conf move --transfers=1 --files-from "$2" "$1" "$drive:$path" --create-empty-src-dirs --delete-empty-src-dirs >> "$LOG_FILE" 2>&1
  shift 2
done
