#!/bin/bash -eu

log "Moving clips to archive..."

NUM_FILES_MOVED=0
NUM_FILES_FAILED=0

function connectionmonitor {
  while true
  do
    # shellcheck disable=SC2034
    for i in {1..5}
    do
      if timeout 6 /root/bin/archive-is-reachable.sh "$ARCHIVE_SERVER"
      then
        # sleep and then continue outer loop
        sleep 5
        continue 2
      fi
    done
    log "connection dead, killing archive-clips"
    # The archive loop might be stuck on an unresponsive server, so kill it hard.
    # (should be no worse than losing power in the middle of an operation)
    kill -9 "$1"
    return
  done
}

function moveclips() {
  cd "$1"

  while IFS= read -r srcfile
  do
    # Remove the 'TeslaCam' folder
    destfile="$srcfile"
    destdir="$ARCHIVE_MOUNT"/$(dirname "$destfile")

    if [ -f "$srcfile" ]
    then
      log "Moving '$srcfile'"
      if [ ! -e "$destdir" ]
      then
        log "Creating output directory '$destdir'"
        if ! mkdir -p "$destdir"
        then
          log "Failed to create '$destdir', check that archive server is writable and has free space"
          return
        fi
      fi

      if mv -f "$srcfile" "$destdir"
      then
        log "Moved '$srcfile'"
        NUM_FILES_MOVED=$((NUM_FILES_MOVED + 1))
      else
        log "Failed to move '$srcfile'"
        NUM_FILES_FAILED=$((NUM_FILES_FAILED + 1))
      fi
    else
      log "$srcfile not found"
    fi
  done < "$2"
}

connectionmonitor $$ &

while [ -n "${1+x}" ]
do
  moveclips "$1" "$2"
  shift 2
done

# Create trigger file for SavedClips
# shellcheck disable=SC2154
if [ -n "${trigger_file_saved+x}" ]
then
  log "Creating SavedClips Trigger File: $ARCHIVE_MOUNT/SavedClips/${trigger_file_saved}"
  touch "$ARCHIVE_MOUNT/SavedClips/${trigger_file_saved}"
fi

# Create trigger file for SentryClips
# shellcheck disable=SC2154
if [ -n "${trigger_file_sentry+x}" ]
then
  log "Creating SentryClips Trigger File: $ARCHIVE_MOUNT/SentryClips/${trigger_file_sentry}"
  touch "$ARCHIVE_MOUNT/SentryClips/${trigger_file_sentry}"
fi

# Create trigger file for Archive Root
# shellcheck disable=SC2154
if [ -n "${trigger_file_any+x}" ]
then
  log "Creating Archive Root Trigger File: $ARCHIVE_MOUNT/${trigger_file_any}"
  touch "$ARCHIVE_MOUNT/${trigger_file_any}"
fi

kill %1

log "Moved $NUM_FILES_MOVED file(s), failed to copy ${NUM_FILES_FAILED}."

if [ $NUM_FILES_MOVED -gt 0 ]
then
  /root/bin/send-push-message "$TESLAUSB_HOSTNAME:" "Moved $NUM_FILES_MOVED dashcam file(s), failed to copy ${NUM_FILES_FAILED}."
fi

log "Finished moving clips to archive."
