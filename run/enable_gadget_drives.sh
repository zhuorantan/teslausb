#!/bin/bash

GADGET_ROOT=/sys/kernel/config/usb_gadget/teslausb

if [ ! -e "$GADGET_ROOT" ]
then
  /root/bin/prepare_gadget.sh
fi

echo "/backingfiles/cam_disk.bin" > "$GADGET_ROOT/functions/mass_storage.0/lun.0/file"
if [ -e "/backingfiles/music_disk.bin" ]
then
  echo "/backingfiles/music_disk.bin" > "$GADGET_ROOT/functions/mass_storage.0/lun.1/file"
fi
