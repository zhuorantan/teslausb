#!/bin/bash

SNAP=/backingfiles/cam_snap_$1
MNT=/mnt/smbexport/$1

function umount_snapshot {
  # for some reason "umount -d" doesn't remove the loop device, so we have to remove it ourselves
  LOOP=$(losetup -j $SNAP | awk '{print $1}' | sed 's/://')
  umount $MNT
  losetup -d $LOOP
  rm $SNAP
  rmdir $MNT
}

umount_snapshot
