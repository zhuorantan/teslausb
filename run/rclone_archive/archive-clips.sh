#!/bin/bash -eu

log "Moving clips to rclone archive..."

source /root/.teslaCamRcloneConfig

while [ -n "${1+x}" ]
do
  # shellcheck disable=SC2154
  rclone --config /root/.config/rclone/rclone.conf move --files-from "$2" "$1" "$drive:$path" --create-empty-src-dirs --delete-empty-src-dirs >> "$LOG_FILE" 2>&1 || echo ""
  shift 2
done

log "Finished moving clips to rclone archive"
