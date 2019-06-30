#!/bin/bash -eu

log "Moving clips to rclone archive..."

source /root/.teslaCamRcloneConfig

NUM_FILES_MOVED=0

for file_name in "$CAM_MOUNT"/TeslaCam/saved* "$CAM_MOUNT"/TeslaCam/SavedClips/*; do
  [ -e "$file_name" ] || continue
  log "Moving $file_name ..."
  rclone --config /root/.config/rclone/rclone.conf move "$file_name" "$drive:$path" >> "$LOG_FILE" 2>&1 || echo ""
  log "Moved $file_name."
  NUM_FILES_MOVED=$((NUM_FILES_MOVED + 1))
done
log "Moved $NUM_FILES_MOVED file(s)."

if [ $NUM_FILES_MOVED -gt 0 ]
then
  /root/bin/send-push-message "TeslaUSB:" "Moved $NUM_FILES_MOVED dashcam file(s)."
fi

log "Finished moving clips to rclone archive"
