#!/bin/bash

SNAP=/backingfiles/cam_snap_$1
MNT=/mnt/smbexport/$1

function mount_snapshot {
  if [ ! -d $MNT ]
  then
    mkdir -p $MNT
  fi

  if mount | grep $MNT
  then
    echo "snapshot already mounted"
  fi

  if [ -e $SNAP ]
  then
    umount $MNT || true
    rm -rf $SNAP
  fi

  # make a copy-on-write snapshot of the current image
  cp --reflink=always /backingfiles/cam_disk.bin $SNAP
  # at this point we have a snapshot of the cam image, which is completely
  # independent of the still in-use image exposed to the car

  # create loopback and scan the partition table, this will create an additional loop
  # device in addition to the main loop device, e.g. /dev/loop0 and /dev/loop0p1
  losetup -P -f $SNAP
  PARTLOOP=$(losetup -j $SNAP | awk '{print $1}' | sed 's/:/p1/')
  fsck $PARTLOOP -- -a

  mount $PARTLOOP $MNT
}

mount_snapshot
