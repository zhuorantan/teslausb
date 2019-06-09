#!/bin/bash

SNAP=/backingfiles/cam_snap_$1
MNT=/mnt/smbexport/$1

/root/bin/release_snapshot.sh $MNT
rm $SNAP
rmdir $MNT
