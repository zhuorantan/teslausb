#!/bin/bash -eu

function log_progress () {
  if typeset -f setup_progress > /dev/null; then
    setup_progress "configure-archive: $1"
  fi
  echo "configure-archive: $1"
}

function configure_archive () {
  log_progress "Configuring the archive..."

  local archive_path="/mnt/archive"
  local music_archive_path="/mnt/musicarchive"

  if [ ! -e "$archive_path" ]
  then
    mkdir "$archive_path"
  fi

  local cifs_version="${cifs_version:-3.0}"

  local credentials_file_path="/root/.teslaCamArchiveCredentials"
  /root/bin/write-archive-configs-to.sh "$credentials_file_path"

  if ! grep -w -q "$archive_path" /etc/fstab
  then
    echo "//$archiveserver/$sharename $archive_path cifs vers=${cifs_version},credentials=${credentials_file_path},iocharset=utf8,file_mode=0777,dir_mode=0777 0" >> /etc/fstab
  fi

  if [ ! -z ${musicsharename:+x} ]
  then
    if [ ! -e "$music_archive_path" ]
    then
      mkdir "$music_archive_path"
    fi
    if ! grep -w -q "$music_archive_path" /etc/fstab
    then
      echo "//$archiveserver/$musicsharename $music_archive_path cifs vers=${cifs_version},credentials=${credentials_file_path},iocharset=utf8,file_mode=0777,dir_mode=0777 0" >> /etc/fstab
    fi
  fi

  log_progress "Configured the archive."
}

configure_archive
