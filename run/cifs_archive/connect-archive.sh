#!/bin/bash -eu

function ensure_archive_is_mounted () {
  log "Ensuring cam archive is mounted..."
  if ensure_mountpoint_is_mounted_with_retry "$ARCHIVE_MOUNT"
  then
    log "Ensured cam archive is mounted."
  else
    log "Failed to mount cam archive."
    return 1
  fi
  if [ -e "$MUSIC_ARCHIVE_MOUNT" ]
  then
    log "Ensuring music archive is mounted..."
    if ensure_mountpoint_is_mounted_with_retry "$MUSIC_ARCHIVE_MOUNT"
    then
      log "Ensured music archive is mounted."
    else
      log "Failed to mount music archive."
      return 1
    fi
  fi
}

ensure_archive_is_mounted
