#!/bin/bash -eu

log "Archiving through rsync..."

source /root/.teslaCamRsyncConfig

num_files_moved=$(rsync -auvh --remove-source-files --no-perms --stats --log-file=/tmp/archive-rsync-cmd.log /mnt/cam/TeslaCam/saved* /mnt/cam/TeslaCam/SavedClips/* $user@$server:$path | awk '/files transferred/{print $NF}')

/root/bin/send-push-message "$num_files_moved"

if (( $num_files_moved > 0 ))
then
  find /mnt/cam/Teslacam/SavedClips/ -depth -type d -empty -exec rmdir "{}" \;
  log "Successfully synced files through rsync."
else
  log "No files to archive through rsync."
fi
