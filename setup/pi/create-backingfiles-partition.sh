#!/bin/bash -eu

function setup_progress () {
  local setup_logfile=/boot/teslausb-headless-setup.log
  local headless_setup=${HEADLESS_SETUP:-false}
  if [ $headless_setup = "true" ]
  then
    echo "$( date ) : $1" >> "$setup_logfile"
  fi
    echo $1
}

if blkid -L backingfiles > /dev/null && blkid -L mutable > /dev/null
then
  # assume these were either created previously by the setup scripts,
  # or manually by the user, and that they're big enough
  setup_progress "using existing backingfiles and mutable partitions"
  return &> /dev/null || exit 0
fi

if ! hash mkfs.btrfs
then
  setup_progress "Can't find btrfs tools. Please install manually or use the correct prebuilt"
  return 1 &> /dev/null || exit 1
fi

BACKINGFILES_MOUNTPOINT="$1"
MUTABLE_MOUNTPOINT="$2"

setup_progress "Checking existing partitions..."
PARTITION_TABLE=$(parted -m /dev/mmcblk0 unit B print)
DISK_LINE=$(echo "$PARTITION_TABLE" | grep -e "^/dev/mmcblk0:")
DISK_SIZE=$(echo "$DISK_LINE" | cut -d ":" -f 2 | sed 's/B//' )

ROOT_PARTITION_LINE=$(echo "$PARTITION_TABLE" | grep -e "^2:")
LAST_ROOT_PARTITION_BYTE=$(echo "$ROOT_PARTITION_LINE" | sed 's/B//g' | cut -d ":" -f 3)

FIRST_BACKINGFILES_PARTITION_BYTE="$(( $LAST_ROOT_PARTITION_BYTE + 1 ))"
LAST_BACKINGFILES_PARTITION_DESIRED_BYTE="$(( $DISK_SIZE - (100 * (2 ** 20)) - 1))"

ORIGINAL_DISK_IDENTIFIER=$( fdisk -l /dev/mmcblk0 | grep -e "^Disk identifier" | sed "s/Disk identifier: 0x//" )

setup_progress "Modifying partition table for backing files partition..."
BACKINGFILES_PARTITION_END_SPEC="$(( $LAST_BACKINGFILES_PARTITION_DESIRED_BYTE / 1000000 ))M"
parted -a optimal -m /dev/mmcblk0 unit B mkpart primary btrfs "$FIRST_BACKINGFILES_PARTITION_BYTE" "$BACKINGFILES_PARTITION_END_SPEC"

setup_progress "Modifying partition table for mutable (writable) partition for script usage..."
MUTABLE_PARTITION_START_SPEC="$BACKINGFILES_PARTITION_END_SPEC"
parted  -a optimal -m /dev/mmcblk0 unit B mkpart primary ext4 "$MUTABLE_PARTITION_START_SPEC" 100%

NEW_DISK_IDENTIFIER=$( fdisk -l /dev/mmcblk0 | grep -e "^Disk identifier" | sed "s/Disk identifier: 0x//" )

setup_progress "Writing updated partitions to fstab and /boot/cmdline.txt"
sed -i "s/${ORIGINAL_DISK_IDENTIFIER}/${NEW_DISK_IDENTIFIER}/g" /etc/fstab
sed -i "s/${ORIGINAL_DISK_IDENTIFIER}/${NEW_DISK_IDENTIFIER}/" /boot/cmdline.txt

setup_progress "Formatting new partitions..."
# needs -f option to force recreating over previously existing partition
mkfs.btrfs -f -L backingfiles /dev/mmcblk0p3
mkfs.ext4 -L mutable /dev/mmcblk0p4

echo "LABEL=backingfiles $BACKINGFILES_MOUNTPOINT btrfs auto,rw,noatime 0 2" >> /etc/fstab
echo "LABEL=mutable $MUTABLE_MOUNTPOINT ext4 auto,rw 0 2" >> /etc/fstab
