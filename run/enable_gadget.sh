#!/bin/bash -eu

function isPi4 {
  grep -q "Pi 4" /sys/firmware/devicetree/base/model
}

function isPi2 {
  grep -q "Zero 2" /sys/firmware/devicetree/base/model
}

if ! configfs_root=$(findmnt -o TARGET -n configfs)
then
  echo "error: configfs not found"
  exit 1
fi
readonly gadget_root="$configfs_root/usb_gadget/teslausb"

# USB supports many languages. 0x409 is US English
readonly lang=0x409

# configuration name can be anything, the convention
# appears to be to use "c"
readonly cfg=c

if [ -d "$gadget_root" ]
then
  echo "already prepared"
  exit 0
fi

modprobe libcomposite

mkdir -p "$gadget_root/configs/$cfg.1"

# common setup
echo 0x1d6b > "$gadget_root/idVendor"  # Linux Foundation
echo 0x0104 > "$gadget_root/idProduct" # Composite Gadget
echo 0x0100 > "$gadget_root/bcdDevice" # v1.0.0
echo 0x0200 > "$gadget_root/bcdUSB"    # USB 2.0
mkdir -p "$gadget_root/strings/$lang"
mkdir -p "$gadget_root/configs/$cfg.1/strings/$lang"
echo "TeslaUSB-$(grep Serial /proc/cpuinfo | awk '{print $3}')" > "$gadget_root/strings/$lang/serialnumber"
echo TeslaUSB > "$gadget_root/strings/$lang/manufacturer"
echo "TeslaUSB Composite Gadget" > "$gadget_root/strings/$lang/product"
echo "TeslaUSB Config" > "$gadget_root/configs/$cfg.1/strings/$lang/configuration"

# A bare Raspberry Pi 4 can peak at at over 700 mA during boot, but idles around
# 450 mA, while a Raspberry Pi 4 with a USB drive can peak at over 1 A during boot
# and idle around 550 mA.
# A Raspberry Pi Zero 2 W can peak at over 300 mA during boot, and has an idle power
# use of about 100 mA.
# A Raspberry Pi Zero W can peak up to 220 mA during boot, and has an idle power
# use of about 80 mA.
# The largest power demand the gadget can report is 500 mA.
if isPi4
then
  echo 500 > "$gadget_root/configs/$cfg.1/MaxPower"
elif isPi2
then
  echo 200 > "$gadget_root/configs/$cfg.1/MaxPower"
else
  echo 100 > "$gadget_root/configs/$cfg.1/MaxPower"
fi

# mass storage setup
mkdir -p "$gadget_root/functions/mass_storage.0"

echo "/backingfiles/cam_disk.bin" > "$gadget_root/functions/mass_storage.0/lun.0/file"
echo "TeslaUSB CAM $(du -h /backingfiles/cam_disk.bin | awk '{print $1}')" > "$gadget_root/functions/mass_storage.0/lun.0/inquiry_string"

# one lun is created by default, so we only need to create the 2nd one
if [ -e "/backingfiles/music_disk.bin" ]
then
  mkdir -p "$gadget_root/functions/mass_storage.0/lun.1"
  echo "/backingfiles/music_disk.bin" > "$gadget_root/functions/mass_storage.0/lun.1/file"
  echo "TeslaUSB MUSIC $(du -h /backingfiles/music_disk.bin | awk '{print $1}')" > "$gadget_root/functions/mass_storage.0/lun.1/inquiry_string"
fi

ln -sf "$gadget_root/functions/mass_storage.0" "$gadget_root/configs/$cfg.1"

# activate
ls /sys/class/udc > "$gadget_root/UDC"
