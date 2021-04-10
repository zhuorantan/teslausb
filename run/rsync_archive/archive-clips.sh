#!/bin/bash -eu

while [ -n "${1+x}" ]
do
  rsync -avhRL --timeout=60 --remove-source-files --no-perms --omit-dir-times --stats \
        --log-file=/tmp/archive-rsync-cmd.log --ignore-missing-args \
        --files-from="$2" "$1" "$RSYNC_USER@$RSYNC_SERVER:$RSYNC_PATH" &> /tmp/rsynclog || [[ "$?" = "24" ]]
  shift 2
done
