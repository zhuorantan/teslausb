#!/bin/bash -eu

source /root/.teslaCamRsyncConfig

while [ -n "${1+x}" ]
do
  # shellcheck disable=SC2154
  rsync -auvhR --timeout=60 --remove-source-files --no-perms --stats --log-file=/tmp/archive-rsync-cmd.log --files-from="$2" "$1" "$user@$server:$path" &> /tmp/rsynclog
  shift 2
done
