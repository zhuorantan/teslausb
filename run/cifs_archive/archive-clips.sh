#!/bin/bash -eu

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
          return 1
        fi
      fi

      if mv -f "$srcfile" "$destdir"
      then
        log "Moved '$srcfile'"
      else
        log "Failed to move '$srcfile'"
        return 1
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

kill %1
