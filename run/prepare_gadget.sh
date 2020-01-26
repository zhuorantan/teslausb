#!/bin/bash -eu

set -x

function isPi4 {
  grep -q "Pi 4" /sys/firmware/devicetree/base/model
}

function isPi2 {
  grep -q "Zero 2" /sys/firmware/devicetree/base/model
}

if [ -d /sys/kernel/config/usb_gadget ]
then
  echo "already prepared"
  exit 0
fi

modprobe libcomposite

cd /sys/kernel/config/usb_gadget
mkdir -p teslausb
cd teslausb

mkdir -p configs/c.1

# common setup
echo 0x1d6b > idVendor  # Linux Foundation
echo 0x0104 > idProduct # Composite Gadget
echo 0x0100 > bcdDevice # v1.0.0
echo 0x0200 > bcdUSB    # USB 2.0
mkdir -p strings/0x409
mkdir -p configs/c.1/strings/0x409
echo "TeslaUSB-$(grep Serial /proc/cpuinfo | awk '{print $3}')" > strings/0x409/serialnumber
echo TeslaUSB > strings/0x409/manufacturer
echo "TeslaUSB Composite Gadget" > strings/0x409/product
echo "Conf 1" > configs/c.1/strings/0x409/configuration

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
  echo 500 > configs/c.1/MaxPower
elif isPi2
then
  echo 200 > configs/c.1/MaxPower
else
  echo 100 > configs/c.1/MaxPower
fi

# mass storage setup
mkdir -p functions/mass_storage.0
# one lun is created by default, so we only need to create the 2nd one
mkdir -p functions/mass_storage.0/lun.1
ln -sf functions/mass_storage.0 configs/c.1

# activate
ls /sys/class/udc > UDC
