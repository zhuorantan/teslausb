#!/bin/bash -eu

log "Moving clips to rclone archive..."

source /root/.teslaCamRcloneConfig

FILE_COUNT=$(cd "$CAM_MOUNT" && find . -maxdepth 4 -path './TeslaCam/SavedClips/*' -type f -o -path './TeslaCam/SentryClips/*' -type f -o -path './TeslaTrackMode' -type f | wc -l)

if [ -d "$CAM_MOUNT"/TeslaCam/SavedClips ]
then
  # shellcheck disable=SC2154
  rclone --config /root/.config/rclone/rclone.conf move "$CAM_MOUNT"/TeslaCam/SavedClips "$drive:$path"/SavedClips/ --create-empty-src-dirs --delete-empty-src-dirs >> "$LOG_FILE" 2>&1 || echo ""
fi

if [ -d "$CAM_MOUNT"/TeslaCam/SentryClips ]
then
  rclone --config /root/.config/rclone/rclone.conf move "$CAM_MOUNT"/TeslaCam/SentryClips "$drive:$path"/SentryClips/ --create-empty-src-dirs --delete-empty-src-dirs >> "$LOG_FILE" 2>&1 || echo ""
fi

if [ -d "$CAM_MOUNT"/TeslaTrackMode ]
then
  rclone --config /root/.config/rclone/rclone.conf move "$CAM_MOUNT"/TeslaTrackMode "$drive:$path"/TeslaTrackMode/ --create-empty-src-dirs --delete-empty-src-dirs >> "$LOG_FILE" 2>&1 || echo ""
fi

FILES_REMAINING=$(cd "$CAM_MOUNT" && find . -maxdepth 4 -path './TeslaCam/SavedClips/*' -type f -o -path './TeslaCam/SentryClips/*' -type f -o -path './TeslaTrackMode' -type f | wc -l)
NUM_FILES_MOVED=$((FILE_COUNT-FILES_REMAINING))

log "Moved $NUM_FILES_MOVED file(s)."
/root/bin/send-push-message "$TESLAUSB_HOSTNAME:" "Moved $NUM_FILES_MOVED dashcam file(s)."

log "Finished moving clips to rclone archive"
