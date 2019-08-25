#!/bin/bash -eu

function log_progress () {
  if typeset -f setup_progress > /dev/null; then
    setup_progress "create-backingfiles: $1"
  fi
  echo "create-backingfiles: $1"
}

log_progress "starting"

CAM_SIZE="$1"
MUSIC_SIZE="$2"
BACKINGFILES_MOUNTPOINT="$3"

log_progress "cam: $CAM_SIZE, music: $MUSIC_SIZE, mountpoint: $BACKINGFILES_MOUNTPOINT"

G_MASS_STORAGE_CONF_FILE_NAME=/etc/modprobe.d/g_mass_storage.conf

function first_partition_offset () {
  local filename="$1"
  local size_in_bytes=$(sfdisk -l -o Size -q --bytes "$1" | tail -1)
  local size_in_sectors=$(sfdisk -l -o Sectors -q "$1" | tail -1)
  local sector_size=$(($size_in_bytes/$size_in_sectors))
  local partition_start_sector=$(sfdisk -l -o Start -q "$1" | tail -1)
  echo $(($partition_start_sector*$sector_size))
}

# Note that this uses powers-of-two rather than the powers-of-ten that are
# generally used to market storage.
function dehumanize () {
  echo $(($(echo $1 | sed 's/G/*1024M/;s/M/*1024K/;s/K/*1024/')))
}

function is_percent() {
  echo "$1" | grep '%' > /dev/null
}

available_space () {
  freespace=$(df --output=avail --block-size=1K $BACKINGFILES_MOUNTPOINT/ | tail -n 1)
  # leave 6 GB of free space for filesystem bookkeeping and snapshotting
  # (in kilobytes so 6M KB)
  # TODO: investigate whether this value can be smaller in general, or
  # when SMB access is not enabled.
  padding=$(dehumanize "6M")
  echo $((freespace-padding))
}

function calc_size () {
  local requestedsize="$1"
  local availablesize="$(available_space)"
  if [ "$availablesize" -lt 0 ]
  then
    echo "0"
    return
  fi
  if is_percent "$requestedsize"
  then
    local percent=$(echo $requestedsize | sed 's/%//')
    requestedsize="$(( $availablesize * $percent / 100 ))"
  else
    requestedsize="$(( $(dehumanize $requestedsize) / 1024 ))"
  fi
  if [ "$requestedsize" -gt "$availablesize" ]
  then
    requestedsize="$availablesize"
  fi
  echo $requestedsize
}

function add_drive () {
  local name="$1"
  local label="$2"
  local size="$3"
  local filename="$4"

  log_progress "Allocating ${size}K for $filename..."
  fallocate -l "$size"K "$filename"
  echo "type=c" | sfdisk "$filename" > /dev/null
  local partition_offset=$(first_partition_offset "$filename")
  losetup -o $partition_offset loop0 "$filename"
  log_progress "Creating filesystem with label '$label'"
  mkfs.vfat /dev/loop0 -F 32 -n "$label"
  losetup -d /dev/loop0

  local mountpoint=/mnt/"$name"

  if [ ! -e "$mountpoint" ]
  then
    mkdir "$mountpoint"
  fi
  sed -i "\@^$filename .*@d" /etc/fstab
  echo "$filename $mountpoint vfat utf8,noauto,users,umask=000,offset=$partition_offset 0 0" >> /etc/fstab
  log_progress "updated /etc/fstab for $mountpoint"
}

function create_teslacam_directory () {
  mount /mnt/cam
  mkdir /mnt/cam/TeslaCam
  umount /mnt/cam
}

CAM_DISK_FILE_NAME="$BACKINGFILES_MOUNTPOINT/cam_disk.bin"
MUSIC_DISK_FILE_NAME="$BACKINGFILES_MOUNTPOINT/music_disk.bin"

# delete existing files, because fallocate doesn't shrink files, and
# because they interfere with the percentage-of-free-space calculation
killall archiveloop || true
modprobe -r g_mass_storage
umount /mnt/cam || true
umount /mnt/music || true
rm -f "$CAM_DISK_FILE_NAME"
rm -f "$MUSIC_DISK_FILE_NAME"

CAM_DISK_SIZE="$(calc_size $CAM_SIZE)"
MUSIC_DISK_SIZE="$(calc_size $MUSIC_SIZE)"

add_drive "cam" "CAM" "$CAM_DISK_SIZE" "$CAM_DISK_FILE_NAME"
log_progress "created camera backing file"

REMAINING_SPACE="$(available_space)"

if [ "$CAM_SIZE" = "100%" ]
then
  MUSIC_DISK_SIZE=0
elif [ "$MUSIC_DISK_SIZE" -gt "$REMAINING_SPACE" ]
then
  MUSIC_DISK_SIZE="$REMAINING_SPACE"
fi

if [ "$REMAINING_SPACE" -ge 1024 -a "$MUSIC_DISK_SIZE" -gt 0 ]
then
  add_drive "music" "MUSIC" "$MUSIC_DISK_SIZE" "$MUSIC_DISK_FILE_NAME"
  log_progress "created music backing file"
  echo "options g_mass_storage file=$MUSIC_DISK_FILE_NAME,$CAM_DISK_FILE_NAME removable=1,1 ro=0,0 stall=0 iSerialNumber=123456" > "$G_MASS_STORAGE_CONF_FILE_NAME"
else
  echo "options g_mass_storage file=$CAM_DISK_FILE_NAME removable=1 ro=0 stall=0 iSerialNumber=123456" > "$G_MASS_STORAGE_CONF_FILE_NAME"
fi

create_teslacam_directory
log_progress "done"
