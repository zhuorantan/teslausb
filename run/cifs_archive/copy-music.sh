#!/bin/bash -eu

SRC="/mnt/musicarchive"
DST="/mnt/music"
LOG="/tmp/rsyncmusiclog.txt"

if ! findmnt --mountpoint $DST
then
  log "$DST not mounted, skipping music sync"
  exit
fi

function connectionmonitor {
  while true
  do
    # shellcheck disable=SC2034
    for i in {1..10}
    do
      if timeout 3 /root/bin/archive-is-reachable.sh "$ARCHIVE_SERVER"
      then
        # sleep and then continue outer loop
        sleep 5
        continue 2
      fi
    done
    log "connection dead, killing copy-music"
    # The archive loop might be stuck on an unresponsive server, so kill it hard.
    # (should be no worse than losing power in the middle of an operation)
    kill -9 "$1"
    return
  done
}

function do_music_sync {
  log "Syncing music from archive..."

  connectionmonitor $$ &

  if ! rsync -rum --no-human-readable --exclude=.fseventsd/*** --exclude=*.DS_Store --exclude=.metadata_never_index --delete --modify-window=2 --info=stats2 "$SRC/" "$DST" &> "$LOG"
  then
    log "rsync failed with error $?"
  fi

  # Stop the connection monitor.
  kill %1

  # remove empty directories
  find $DST -depth -type d -empty -delete || true

  # parse log for relevant info
  declare -i NUM_FILES_COPIED
  NUM_FILES_COPIED=$(($(sed -n -e 's/\(^Number of regular files transferred: \)\([[:digit:]]\+\).*/\2/p' "$LOG")))
  declare -i NUM_FILES_DELETED
  NUM_FILES_DELETED=$(($(sed -n -e 's/\(^Number of deleted files: [[:digit:]]\+ (reg: \)\([[:digit:]]\+\)*.*/\2/p' "$LOG")))
  declare -i TOTAL_FILES
  TOTAL_FILES=$(sed -n -e 's/\(^Number of files: [[:digit:]]\+ (reg: \)\([[:digit:]]\+\)*.*/\2/p' "$LOG")
  declare -i NUM_FILES_ERROR
  NUM_FILES_ERROR=$(($(grep -c "failed to open" $LOG || true)))

  declare -i NUM_FILES_SKIPPED=$((TOTAL_FILES-NUM_FILES_COPIED))
  NUM_FILES_COPIED=$((NUM_FILES_COPIED-NUM_FILES_ERROR))

  log "Copied $NUM_FILES_COPIED music file(s), deleted $NUM_FILES_DELETED, skipped $NUM_FILES_SKIPPED previously-copied files, and encountered $NUM_FILES_ERROR errors."

  if [ $NUM_FILES_COPIED -ne 0 ] || [ $NUM_FILES_DELETED -ne 0 ] || [ $NUM_FILES_ERROR -ne 0 ]
  then
    /root/bin/send-push-message "$TESLAUSB_HOSTNAME:" "Copied $NUM_FILES_COPIED music file(s), deleted $NUM_FILES_DELETED, skipped $NUM_FILES_SKIPPED previously-copied files, and encountered $NUM_FILES_ERROR errors."
  fi
}

if ! do_music_sync
then
  log "Error while syncing music"
fi
