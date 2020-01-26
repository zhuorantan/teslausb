#!/bin/bash -eu

set -x

function isPi4 {
  grep -q "Pi 4" /sys/firmware/devicetree/base/model
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
if isPi4
then
  echo 500 > configs/c.1/MaxPower
else
  echo 120 > configs/c.1/MaxPower
fi

# mass storage setup
mkdir -p functions/mass_storage.0
# one lun is created by default, so we only need to create the 2nd one
mkdir -p functions/mass_storage.0/lun.1
ln -sf functions/mass_storage.0 configs/c.1

# activate
ls /sys/class/udc > UDC
