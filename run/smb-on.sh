#!/bin/bash

SRC=/backingfiles/cam_disk.bin
SNAP=/backingfiles/cam_snap_$1
MNT=/mnt/smbexport/$1

/root/bin/mount_snapshot.sh $SRC $SNAP $MNT
