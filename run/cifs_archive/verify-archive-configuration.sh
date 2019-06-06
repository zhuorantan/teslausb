#!/bin/bash -eu

function log_progress () {
  if typeset -f setup_progress > /dev/null; then
    setup_progress "verify-archive-configuration: $1"
  fi
  echo "verify-archive-configuration: $1"
}

function check_archive_server_reachable () {
  log_progress "Verifying that the archive server $archiveserver is reachable..."
  local serverunreachable=false
  hping3 -c 1 -S -p 445 "$archiveserver" 1>/dev/null 2>&1 || serverunreachable=true

  if [ "$serverunreachable" = true ]
  then
    log_progress "STOP: The archive server $archiveserver is unreachable. Try specifying its IP address instead."
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

  local cifs_version="${cifs_version:-3.0}"

  local tmp_credentials_file_path="/tmp/teslaCamArchiveCredentials"
  /root/bin/write-archive-configs-to.sh "$tmp_credentials_file_path"

  local mount_failed=false
  log_progress "Mount command-line: "
  log_progress "mount -t cifs //$1/$2 $test_mount_location -o vers=${cifs_version},credentials=${tmp_credentials_file_path},iocharset=utf8,file_mode=0777,dir_mode=0777"
  mount -t cifs "//$1/$2" "$test_mount_location" -o "vers=${cifs_version},credentials=${tmp_credentials_file_path},iocharset=utf8,file_mode=0777,dir_mode=0777" || mount_failed=true

  if [ "$mount_failed" = true ]
  then
    log_progress "STOP: The archive couldn't be mounted with CIFS version ${cifs_version}. Try specifying a lower number for the CIFS version like this:"
    log_progress "  export cifs_version=2.1"
    log_progress "Other versions you can try are 2.0 and 1.0"
    exit 1
  fi

  log_progress "The archive share is mountable."

  umount "$test_mount_location"
}

function install_required_packages () {
  log_progress "Installing/updating required packages if needed"
  apt-get -y --force-yes install hping3
  log_progress "Done"
}

install_required_packages

check_archive_server_reachable
check_archive_mountable "$archiveserver" "$sharename"
if [ ! -z ${musicsharename:+x} ]
then
  check_archive_mountable "$archiveserver" "$musicsharename"
fi
