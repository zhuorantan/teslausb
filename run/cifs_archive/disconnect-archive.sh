#!/bin/bash -eu

# unmount the archive. Without this, the archive mounts can get into a
# state where the archive is reachable via the network, appears to be
# mounted, but the mount is inoperable and any attempt to access it
# results in a "host is down" message.
# Run this in the background, since unmounting can hang, which would
# block a return to archiveloop.

{
  log "unmounting $ARCHIVE_MOUNT"
  if ! umount -f -l "$ARCHIVE_MOUNT"
  then
    log "unmount failed"
  fi

  if [ -e "$MUSIC_ARCHIVE_MOUNT" ]
  then
    log "unmounting $MUSIC_ARCHIVE_MOUNT"
    if ! umount -f -l "$MUSIC_ARCHIVE_MOUNT"
    then
      log "unmount failed"
    fi
  fi
} &

