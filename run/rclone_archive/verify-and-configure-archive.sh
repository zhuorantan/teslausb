#!/bin/bash -eu

function verify_configuration () {
    echo "Verifying rlcone configuration..."
    if ! [ -e "/root/.config/rclone/rclone.conf" ]
    then
        echo "STOP: rclone config was not found. did you configure rclone correctly?"
        exit 1
    fi

    if ! rclone lsd "$RCLONE_DRIVE": | grep -q "$RCLONE_PATH"
    then
        echo "STOP: Could not find the $RCLONE_DRIVE:$RCLONE_PATH"
        exit 1
    fi
}

verify_configuration

function configure_archive () {
  echo "Configuring rclone archive..."

  local config_file_path="/root/.teslaCamRcloneConfig"
  /root/bin/write-archive-configs-to.sh "$config_file_path"

  if [ ! -L "/root/.config/rclone" ] && [ -e "/root/.config/rclone" ]
  then
    echo "Moving rclone configs into /mutable"
    mv /root/.config/rclone /mutable/configs
    ln -s /mutable/configs/rclone /root/.config/rclone
  fi

  echo "Done"
}

configure_archive
