#!/bin/bash -eu

function disable_drives {
  echo "" > "$GADGET_ROOT/functions/mass_storage.0/lun.0/file"
  echo "" > "$GADGET_ROOT/functions/mass_storage.0/lun.1/file"
}

GADGET_ROOT=/sys/kernel/config/usb_gadget/teslausb
if ! disable_drives &> /dev/null
then
  # the host likely issued a "prevent media removal" command, so we'll have to disable the entire gadget first
  echo "" > "$GADGET_ROOT/UDC"
  disable_drives
  ls /sys/class/udc/ > "$GADGET_ROOT/UDC"
fi
