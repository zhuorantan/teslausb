#!/bin/bash -eu

if [ "${BASH_SOURCE[0]}" != "$0" ]
then
  echo "${BASH_SOURCE[0]} must be executed, not sourced"
  return 1 # shouldn't use exit when sourced
fi

if [ "${FLOCKED:-}" != "$0" ]
then
  mkdir -p /backingfiles/snapshots
  if FLOCKED="$0" flock -E 99 /backingfiles/snapshots "$0" "$@" || case "$?" in
  99) echo "failed to lock snapshots dir"
      exit 99
      ;;
  *)  exit $?
      ;;
  esac
  then
    # success
    exit 0
  fi
fi

function linksnapshotfiletorecents {
  local file=$1
  local curmnt=$2
  local finalmnt=$3
  local recents=/backingfiles/TeslaCam/RecentClips

  filename=${file##/*/}
  filedate=${filename:0:10}
  if [ ! -d "$recents/$filedate" ]
  then
    mkdir -p "$recents/$filedate"
  fi
  ln -sf "${file/"$curmnt"/$finalmnt}" "$recents/$filedate"
}

function make_links_for_snapshot {
  local saved=/backingfiles/TeslaCam/SavedClips
  local sentry=/backingfiles/TeslaCam/SentryClips
  if [ ! -d $saved ]
  then
    mkdir -p $saved
  fi
  if [ ! -d $sentry ]
  then
    mkdir -p $sentry
  fi
  local curmnt="$1"
  local finalmnt="$2"
  log "making links for $curmnt, retargeted to $finalmnt"
  local restore_nullglob
  restore_nullglob=$(shopt -p nullglob)
  shopt -s nullglob
  for f in "$curmnt/TeslaCam/RecentClips/"*
  do
    #log "linking $f"
    linksnapshotfiletorecents "$f" "$curmnt" "$finalmnt"
  done
  # also link in any files that were moved to SavedClips
  for f in "$curmnt/TeslaCam/SavedClips"/*/*
  do
    #log "linking $f"
    linksnapshotfiletorecents "$f" "$curmnt" "$finalmnt"
    # also link it into a SavedClips folder
    local eventfolder=${f%/*}
    local eventtime=${eventfolder##/*/}
    if [ ! -d "$saved/$eventtime" ]
    then
      mkdir -p "$saved/$eventtime"
    fi
    ln -sf "${f/$curmnt/$finalmnt}" "$saved/$eventtime"
  done
  # and the same for SentryClips
  for f in "$curmnt/TeslaCam/SentryClips/"*/*
  do
    #log "linking $f"
    linksnapshotfiletorecents "$f" "$curmnt" "$finalmnt"
    local eventfolder=${f%/*}
    local eventtime=${eventfolder##/*/}
    if [ ! -d "$sentry/$eventtime" ]
    then
      mkdir -p "$sentry/$eventtime"
    fi
    ln -sf "${f/$curmnt/$finalmnt}" "$sentry/$eventtime"
  done
  log "made all links for $curmnt"
  $restore_nullglob
}

function snapshot {
  # Only take a snapshot if the remaining free space is greater than
  # the size of the cam disk image. Delete older snapshots if necessary
  # to achieve that.
  # todo: this could be put in a background task and with a lower free
  # space requirement, to delete old snapshots just before running out
  # of space and thus make better use of space
  local imgsize
  imgsize=$(eval "$(stat --format="echo \$((%b*%B))" /backingfiles/cam_disk.bin)")
  while true
  do
    local freespace
    freespace=$(eval "$(stat --file-system --format="echo \$((%f*%S))" /backingfiles/cam_disk.bin)")
    if [ "$freespace" -gt "$imgsize" ]
    then
      break
    fi
    if ! stat /backingfiles/snapshots/snap-*/snap.bin > /dev/null 2>&1
    then
      log "warning: low space for snapshots"
      break
    fi
    oldest=$(find /backingfiles/snapshots -maxdepth 1 -name 'snap-*' | sort | head -1)
    log "low space, deleting $oldest"
    /root/bin/release_snapshot.sh "$oldest"
    rm -rf "$oldest"
  done

  local oldnum=-1
  local newnum=0
  if stat /backingfiles/snapshots/snap-*/snap.bin > /dev/null 2>&1
  then
    oldnum=$(find /backingfiles/snapshots/snap-* -maxdepth 1 -name snap.bin | sort | tail -1 | tr -c -d '[:digit:]' | sed 's/^0*//' )
    newnum=$((oldnum + 1))
  fi
  local oldname
  local newsnapdir
  oldname=/backingfiles/snapshots/snap-$(printf "%06d" "$oldnum")/snap.bin
  newsnapdir=/backingfiles/snapshots/snap-$(printf "%06d" $newnum)
  newsnapmnt=/tmp/snapshots/snap-$(printf "%06d" $newnum)

  local tmpsnapdir=/backingfiles/snapshots/newsnap
  local tmpsnapname=$tmpsnapdir/snap.bin
  log "taking snapshot of cam disk in $newsnapdir"
  rm -rf "$tmpsnapdir"
  /root/bin/mount_snapshot.sh /backingfiles/cam_disk.bin "$tmpsnapname" "$newsnapmnt"
  log "took snapshot"

  # check whether this snapshot is actually different from the previous one
  find "$newsnapmnt/TeslaCam" -type f -printf '%s %P\n' > "/tmp/snap.bin.toc"
  log "comparing new snapshot with $oldname"
  if [[ ! -e "$oldname.toc" ]] || diff "$oldname.toc" "/tmp/snap.bin.toc" | grep -e '^>'
  then
    ln -s "$newsnapmnt" "$tmpsnapdir/mnt"
    make_links_for_snapshot "$newsnapmnt" "$newsnapdir/mnt"
    mv "$tmpsnapdir" "$newsnapdir"
    mv /tmp/snap.bin.toc "$newsnapdir"
  else
    log "new snapshot is identical to previous one, discarding"
    /root/bin/release_snapshot.sh "$newsnapmnt"
    rm -rf "$tmpsnapdir"
  fi
}

if ! snapshot
then
  log "failed to take snapshot"
fi

