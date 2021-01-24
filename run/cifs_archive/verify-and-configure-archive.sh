#!/bin/bash -eu

VERS_OPT=
SEC_OPT=

function log_progress () {
  if declare -F setup_progress > /dev/null
  then
    setup_progress "verify-and-configure-archive: $*"
  fi
  echo "verify-and-configure-archive: $1"
}

function check_archive_server_reachable () {
  log_progress "Verifying that the archive server $ARCHIVE_SERVER is reachable..."
  local serverunreachable=false
  hping3 -c 1 -S -p 445 "$ARCHIVE_SERVER" 1>/dev/null 2>&1 || serverunreachable=true

  if [ "$serverunreachable" = true ]
  then
    log_progress "STOP: The archive server $ARCHIVE_SERVER is unreachable. Try specifying its IP address instead."
    exit 1
  fi

  log_progress "The archive server is reachable."
}

function check_archive_mountable () {
  local test_mount_location="/tmp/archivetestmount"

  log_progress "Verifying that the archive share is mountable..."

  if [ ! -e "$test_mount_location" ]
  then
    mkdir "$test_mount_location"
  fi

  local tmp_credentials_file_path="/tmp/teslaCamArchiveCredentials"
  /tmp/write-archive-configs-to.sh "$tmp_credentials_file_path"

  local mounted=false
  local try_versions="${cifs_version:-@@ default 3.0 2.1 2.0 1.0}"
  local try_secs="${cifs_sec:-@@ ntlmssp ntlmv2 ntlm}"

  echo "Trying all combinations of vers=($try_versions) and sec=($try_secs)"
  for vers in $try_versions
  do
    for sec in $try_secs
    do
      versopt=""
      secopt=""
      if [ "$vers" != "@@" ]
      then
        versopt="vers=$vers"
      fi
      if [ "$sec" != "@@" ]
      then
        secopt="sec=$sec"
      fi
      local commandline="mount -t cifs '//$1/$2' '$test_mount_location' -o 'credentials=${tmp_credentials_file_path},iocharset=utf8,file_mode=0777,dir_mode=0777,$versopt,$secopt'"
      log_progress "Trying mount command-line:"
      log_progress "$commandline"
      if eval "$commandline"
      then
        mounted=true
        break 2
      fi
    done
  done
  if [ "$mounted" = false ]
  then
    log_progress "STOP: no working combination of vers and sec mount options worked"
    exit 1
  else
    log_progress "The archive share is mountable using: $commandline"
    # the music archive must be mountable with the same mount options
    # so fix the options now
    export cifs_version=$vers
    export cifs_sec=$sec
    VERS_OPT=$versopt
    SEC_OPT=$secopt
  fi

  umount "$test_mount_location"
}

function install_required_packages () {
  log_progress "Installing/updating required packages if needed"
  apt-get -y --force-yes install hping3
  log_progress "Done"
}

install_required_packages

check_archive_server_reachable

check_archive_mountable "$ARCHIVE_SERVER" "$SHARE_NAME"
# shellcheck disable=SC2154
if [ -n "${musicsharename:+x}" ]
then
  if [ "$MUSIC_SIZE" = "0" ]
  then
    log_progress "STOP: musicsharename specified but no music drive size specified"
    exit 1
  fi
  check_archive_mountable "$ARCHIVE_SERVER" "$musicsharename"
fi

function configure_archive () {
  log_progress "Configuring the archive..."

  local archive_path="/mnt/archive"
  local music_archive_path="/mnt/musicarchive"

  if [ ! -e "$archive_path" ]
  then
    mkdir "$archive_path"
  fi

  local credentials_file_path="/root/.teslaCamArchiveCredentials"
  /tmp/write-archive-configs-to.sh "$credentials_file_path"

  sed -i "/^.*\.teslaCamArchiveCredentials.*$/ d" /etc/fstab
  local sharenameforstab="${SHARE_NAME// /\\040}"
  echo "//$ARCHIVE_SERVER/$sharenameforstab $archive_path cifs noauto,credentials=${credentials_file_path},iocharset=utf8,file_mode=0777,dir_mode=0777,$VERS_OPT,$SEC_OPT 0" >> /etc/fstab

  if [ -n "${musicsharename:+x}" ]
  then
    if [ ! -e "$music_archive_path" ]
    then
      mkdir "$music_archive_path"
    fi
    local musicsharenameforstab="${musicsharename// /\\040}"
    echo "//$ARCHIVE_SERVER/$musicsharenameforstab $music_archive_path cifs noauto,credentials=${credentials_file_path},iocharset=utf8,file_mode=0777,dir_mode=0777,$VERS_OPT,$SEC_OPT 0" >> /etc/fstab
  fi
  log_progress "Configured the archive."
}

configure_archive
