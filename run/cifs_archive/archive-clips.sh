#!/bin/bash -eu

log "Moving clips to archive..."

NUM_FILES_MOVED=0
NUM_FILES_FAILED=0
NUM_FILES_DELETED=0

function moveclips() {
  ROOT="$1"
  PATTERN="$2"

  if [ ! -d "$ROOT" ]
  then
    log "$ROOT does not exist, skipping"
    return
  fi

  while read file_name
  do
    if [ -d "$ROOT/$file_name" ]
    then
      log "Creating output directory '$file_name'"
      mkdir -p "$ARCHIVE_MOUNT/$file_name"
    elif [ -f "$ROOT/$file_name" ]
    then
      size=$(stat -c%s "$ROOT/$file_name")
      if [ $size -lt 100000 ]
      then
        log "'$file_name' is only $size bytes"
        rm "$ROOT/$file_name"
        NUM_FILES_DELETED=$((NUM_FILES_DELETED + 1))
      else
        log "Moving '$file_name'"
        outdir=$(dirname "$file_name")
        if mv -f "$ROOT/$file_name" "$ARCHIVE_MOUNT/$outdir"
        then
          log "Moved '$file_name'"
          NUM_FILES_MOVED=$((NUM_FILES_MOVED + 1))
        else
          log "Failed to move '$file_name'"
          NUM_FILES_FAILED=$((NUM_FILES_FAILED + 1))
        fi
      fi
    else
      log "$file_name not found"
    fi
  done <<< $(cd "$ROOT"; find $PATTERN)
}

# legacy file name pattern, firmware 2018.*
moveclips "$CAM_MOUNT/TeslaCam" 'saved*'

# new file name pattern, firmware 2019.*
moveclips "$CAM_MOUNT/TeslaCam/SavedClips" '*'

# delete empty directories under SavedClips
rmdir --ignore-fail-on-non-empty "$CAM_MOUNT/TeslaCam/SavedClips"/* || true

log "Moved $NUM_FILES_MOVED file(s), failed to copy $NUM_FILES_FAILED, deleted $NUM_FILES_DELETED."

if [ $NUM_FILES_MOVED -gt 0 ]
then
  /root/bin/send-push-message "$NUM_FILES_MOVED"
fi

log "Finished moving clips to archive."
