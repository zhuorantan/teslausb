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

  if blkid -L backingfiles > /dev/null && blkid -L mutable > /dev/null
  then
    # assume these were either created previously by the setup scripts,
    # or manually by the user, and that they're big enough
    setup_progress "using existing backingfiles and mutable partitions"
    return
  fi

  local available_space="$( parted -m /dev/mmcblk0 u b print free | tail -1 | cut -d ":" -f 4 | sed 's/B//g' )"

  if [ "$available_space" -lt  4294967296 ]
  then
    setup_progress "STOP: The MicroSD card is too small: $available_space bytes available."
    setup_progress "$(parted -m /dev/mmcblk0 print)"
    exit 1
  fi

  setup_progress "There is sufficient space available."
}

function check_setup_teslausb () {
  if ! grep selfupdate /root/bin/setup-teslausb
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
    return 1
  fi
}

check_setup_teslausb

check_variable "camsize"

check_available_space
