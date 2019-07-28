#!/bin/bash -eu

log "Copying music from archive..."

NUM_FILES_COPIED=0
NUM_FILES_SKIPPED=0
NUM_FILES_ERROR=0
SRC="/mnt/musicarchive"
DST="/mnt/music"

while read file_name
do
  if [ ! -e "$DST/$file_name" ]
  then
    dir=$(dirname "$file_name")
    if ! mkdir -p "$DST/$dir"
    then
      log "couldn't make directory $DST/$dir"
      NUM_FILES_ERROR=$((NUM_FILES_ERROR + 1))
      continue
    fi
    if ! cp "$SRC/$file_name" "$DST/$dir/__tmp__"
    then
      log "Couldn't copy $SRC/$file_name"
      NUM_FILES_ERROR=$((NUM_FILES_ERROR + 1))
      continue
    fi
    if ! mv "$DST/$dir/__tmp__" "$DST/$file_name"
    then
      log "Couldn't move to $DST/$file_name"
      NUM_FILES_ERROR=$((NUM_FILES_ERROR + 1))
      continue
    fi
    NUM_FILES_COPIED=$((NUM_FILES_COPIED + 1))
  else
    NUM_FILES_SKIPPED=$((NUM_FILES_SKIPPED + 1))
  fi
done <<< "$(cd "$SRC"; find * -type f)"

log "Copied $NUM_FILES_COPIED music file(s), skipped $NUM_FILES_SKIPPED previously-copied files, encountered $NUM_FILES_ERROR errors."

if [ $NUM_FILES_COPIED -gt 0 ]
then
  /root/bin/send-push-message "TeslaUSB:" "Copied $NUM_FILES_COPIED music file(s), skipped $NUM_FILES_SKIPPED previously-copied files, encountered $NUM_FILES_ERROR errors."
fi
