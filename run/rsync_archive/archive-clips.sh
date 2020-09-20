#!/bin/bash -eu

log "Archiving through rsync..."

source /root/.teslaCamRsyncConfig

declare -i num_files_moved=0

while [ -n "${1+x}" ]
do
  # shellcheck disable=SC2154
  rsync -auvhR --timeout=60 --remove-source-files --no-perms --stats --log-file=/tmp/archive-rsync-cmd.log --files-from="$2" "$1" "$user@$server:$path" &> /tmp/rsynclog
  moved=$(awk '/files transferred/{print $NF}' < /tmp/rsynclog)
  num_files_moved=$((num_files_moved + moved))
  shift 2
done

if (( num_files_moved > 0 ))
then
  log "Successfully synced files through rsync."
  /root/bin/send-push-message "$TESLAUSB_HOSTNAME:" "Moved $num_files_moved dashcam files"
else
  log "No files archived."
fi
