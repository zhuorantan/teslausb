#!/bin/bash -eu

NAME=$(basename "$1")
IMAGE="/backingfiles/snapshots/$NAME/snap.bin"
umount "$IMAGE" || true

# delete the snapshot folders
rm -rf "/backingfiles/snapshots/$NAME"

# delete all obsolete links
find /backingfiles/TeslaCam/ -lname "*${NAME}*" -delete || true

# delete all Sentry, saved and recent folders that are now empty
find /backingfiles/TeslaCam/ -mindepth 2 -depth -type d -empty -exec rmdir "{}" \; || true
