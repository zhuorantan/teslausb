#!/bin/bash -eu
set -x

if [ ! -d /sys/kernel/config/usb_gadget ]
then
  echo "already released"
  exit 0
fi

cd /sys/kernel/config/
echo "" > usb_gadget/teslausb/UDC
rmdir usb_gadget/teslausb/configs/c.1/strings/0x409
rm -f  usb_gadget/teslausb/configs/c.1/mass_storage.0
rmdir usb_gadget/teslausb/functions/mass_storage.0/lun.1
rmdir usb_gadget/teslausb/functions/mass_storage.0
rmdir usb_gadget/teslausb/configs/c.1
rmdir usb_gadget/teslausb/strings/0x409
rmdir usb_gadget/teslausb

modprobe -r usb_f_mass_storage libcomposite
