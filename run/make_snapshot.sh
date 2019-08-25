#!/bin/bash -eu

if [ "$BASH_SOURCE" != "$0" ]
then
  echo "$BASH_SOURCE must be executed, not sourced"
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

function make_links_for_snapshot {
  local collection=/backingfiles/TeslaCam/RecentClips
  mkdir -p $collection
  local curmnt="$1"
  local finalmnt="$2"
  log "making links for $curmnt, retargeted to $finalmnt"
  if stat $curmnt/TeslaCam/RecentClips/* > /dev/null
  then
    for f in $curmnt/TeslaCam/RecentClips/*
    do
      log "linking $f"
      ln -sf "$(echo $f | sed "s@$curmnt@$finalmnt@")" $collection
    done
  fi
  # also link in any files that were moved to SavedClips
  if stat $curmnt/TeslaCam/SavedClips/*/* > /dev/null
  then
    for f in $curmnt/TeslaCam/SavedClips/*/*
    do
      log "linking $f"
      ln -sf $(echo $f | sed "s@$curmnt@$finalmnt@") $collection
    done
  fi
  log "made all links for $curmnt"
}

function snapshot {
  # Only take a snapshot if the remaining free space is greater than
  # the size of the cam disk image. Delete older snapshots if necessary
  # to achieve that.
  # todo: this could be put in a background task and with a lower free
  # space requirement, to delete old snapshots just before running out
  # of space and thus make better use of space
  local imgsize=$(eval $(stat --format='echo $((%b*%B))' /backingfiles/cam_disk.bin))
  while true
  do
    local freespace=$(eval $(stat --file-system --format='echo $((%f*%S))' /backingfiles/cam_disk.bin))
    if [ $freespace -gt $imgsize ]
    then
      break
    fi
    if ! stat /backingfiles/snapshots/snap-*/snap.bin > /dev/null 2>&1
    then
      log "warning: low space for snapshots"
      break
    fi
    oldest=$(ls -ldC1 /backingfiles/snapshots/snap-* | head -1)
    log "low space, deleting $oldest"
    /root/bin/release_snapshot.sh "$oldest/mnt"
    rm -rf "$oldest"
  done

  local oldnum=-1
  local newnum=0
  if stat /backingfiles/snapshots/snap-*/snap.bin > /dev/null 2>&1
  then
    oldnum=$(ls -lC1 /backingfiles/snapshots/snap-*/snap.bin | tail -1 | tr -c -d '[:digit:]' | sed 's/^0*//' )
    newnum=$((oldnum + 1))
  fi
  local oldname=/backingfiles/snapshots/snap-$(printf "%06d" $oldnum)/snap.bin
  local newsnapdir=/backingfiles/snapshots/snap-$(printf "%06d" $newnum)
  local newname=$newsnapdir/snap.bin
  local tmpsnapdir=/backingfiles/snapshots/newsnap
  local tmpsnapname=$tmpsnapdir/snap.bin
  local tmpsnapmnt=$tmpsnapdir/mnt
  log "taking snapshot of cam disk: $newname"
  rm -rf "$tmpsnapdir"
  /root/bin/mount_snapshot.sh /backingfiles/cam_disk.bin "$tmpsnapname" "$tmpsnapmnt"
  log "took snapshot"

  # check whether this snapshot is actually different from the previous one
  find "$tmpsnapmnt/TeslaCam" -type f -printf '%s %P\n' > "$tmpsnapname.toc"
  log "comparing $oldname.toc and $tmpsnapname.toc"
  if [[ ! -e "$oldname.toc" ]] || diff "$oldname.toc" "$tmpsnapname.toc" | grep -e '^>'
  then
    make_links_for_snapshot "$tmpsnapmnt" "$newsnapdir/mnt"
    mv "$tmpsnapdir" "$newsnapdir"
  else
    log "new snapshot is identical to previous one, discarding"
    /root/bin/release_snapshot.sh "$tmpsnapmnt"
    rm -rf "$tmpsnapdir"
  fi
}

if ! snapshot
then
  log "failed to take snapshot"
fi

