#!/bin/bash -eu

# for some reason "umount -d" doesn't remove the loop device, so we have to remove it ourselves
NAME=$(basename "$1")
LOOPPART=$(mount | grep -w "$NAME" | awk '{print $1}')
LOOPROOT=${LOOPPART/p1/}
MNT=$(findmnt -o target -n "$LOOPPART")
umount "$MNT"
losetup -d "$LOOPROOT"

# delete the snapshot folders
rm -rf "/backingfiles/snapshots/$NAME" "/tmp/snapshots/$NAME"

# delete all dead links
find /backingfiles/TeslaCam/ -depth -xtype l -delete || true

# delete all Sentry, saved and recent folders that are now empty
find /backingfiles/TeslaCam/ -mindepth 2 -depth -type d -empty -exec rmdir "{}" \;
