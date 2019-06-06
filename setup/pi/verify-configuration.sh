#!/bin/bash -eu

function check_variable () {
  local var_name="$1"
  if [ -z "${!var_name+x}" ]
  then
    setup_progress "STOP: Define the variable $var_name like this: export $var_name=value"
    exit 1
  fi
}

function check_available_space () {
  setup_progress "Verifying that there is sufficient space available on the MicroSD card..."

  # The following assumes that the root and boot partitions are adjacent at the start
  # of the disk, and that all the free space is at the end.

  local totalsize=$(blockdev --getsize64 /dev/mmcblk0)
  local part1size=$(blockdev --getsize64 /dev/mmcblk0p1)
  local part2size=$(blockdev --getsize64 /dev/mmcblk0p2)

  local available_space=$(($totalsize - $part1size - $part2size))

  # Require at least 12 GB of available space.
  if [ "$available_space" -lt  $(( (1<<30) * 12)) ]
  then
    setup_progress "STOP: The MicroSD card is too small: $available_space bytes available."
    setup_progress "$(parted /dev/mmcblk0 print)"
    exit 1
  fi

  setup_progress "There is sufficient space available."
}

function check_setup_teslausb () {
  if [ ! -e /root/bin/setup-teslausb ]
  then
    setup_progress "STOP: setup-teslausb is not in /root/bin"
    exit 1
  fi
  if ! grep selfupdate /root/bin/setup-teslausb > /dev/null
  then
    setup_progress "setup-teslausb is outdated, attempting update"
    if curl --fail -s -o /root/bin/setup-teslausb.new https://raw.githubusercontent.com/marcone/teslausb/main-dev/setup/pi/setup-teslausb
    then
      if /root/bin/remountfs_rw > /dev/null && mv /root/bin/setup-teslausb.new /root/bin/setup-teslausb && chmod +x /root/bin/setup-teslausb
      then
        setup_progress "updated setup-teslausb"
        setup_progress "restarting updated setup-teslausb"
        /root/bin/setup-teslausb
        exit 0
      fi
    fi
    setup_progress "STOP: failed to update setup-teslausb"
    exit 1
  fi
}

check_setup_teslausb

check_variable "camsize"

check_available_space
