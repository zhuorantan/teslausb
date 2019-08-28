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

  # Ensure that /root/.config/rclone is a directory not a symlink
  if [ ! -L "/root/.config/rclone" ] && [ -d "/root/.config/rclone" ]
  then
    echo "Moving rclone configs into /mutable"
    # Creating only configs dir so we can move the rclone dir into it
    mkdir -p /mutable/configs
    # Moving the directory itself to ensure the link creation works correctly
    mv /root/.config/rclone /mutable/configs/
    # Creating link, this requires the directory /root/.config/rclone to be nonexistent
    ln -s /mutable/configs/rclone /root/.config/rclone
  fi

  echo "Done"
}

configure_archive
