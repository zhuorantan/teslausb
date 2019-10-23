#!/bin/bash -eu

log "syncing clips to archive..."

num_files_moved=$(rsync -auvh --timeout=60 --remove-source-files --no-perms --stats --log-file=/tmp/archive-rsync-cmd.log $CAM_MOUNT/TeslaCam/SentryClips $CAM_MOUNT/TeslaCam/SavedClips $ARCHIVE_MOUNT/ | awk '/files transferred/{print $NF}')

if (( $num_files_moved > 0 ))
then
  find $CAM_MOUNT/Teslacam/SavedClips/ $CAM_MOUNT/Teslacam/SentryClips/ -depth -type d -empty -exec rmdir "{}" \;
  log "Successfully synced $num_files_moved files through rsync."
  /root/bin/send-push-message "TeslaUSB:" "Moved $num_files_moved dashcam files"
else
  log "No files archived."
fi


