#!/bin/bash -eu

function log_progress () {
  if declare -F setup_progress > /dev/null
  then
    setup_progress "create-backingfiles-partition: $1"
  fi
  echo "create-backingfiles-partition: $1"
}

# install XFS tools if needed
if ! hash mkfs.xfs
then
  apt-get -y --force-yes install xfsprogs
fi

# Will check for USB Drive before running sd card
if [ -n "$USB_DRIVE" ]
then
  log_progress "USB_DRIVE is set to $USB_DRIVE"
  # Check if backingfiles and mutable partitions exist
  if [ /dev/disk/by-label/backingfiles -ef /dev/sda2 ] && [ /dev/disk/by-label/mutable -ef /dev/sda1 ]
  then
    log_progress "Looks like backingfiles and mutable partitions already exist. Skipping partition creation."
  else
    log_progress "WARNING !!! This will delete EVERYTHING in $USB_DRIVE."
    wipefs -afq "$USB_DRIVE"
    parted "$USB_DRIVE" --script mktable gpt
    log_progress "$USB_DRIVE fully erased. Creating partitions..."
    parted -a optimal -m /dev/sda mkpart primary ext4 '0%' 2GB
    parted -a optimal -m /dev/sda mkpart primary ext4 2GB '100%'
    log_progress "Backing files and mutable partitions created."

    log_progress "Formatting new partitions..."
    # Force creation of filesystems even if previous filesystem appears to exist
    mkfs.ext4 -F -L mutable /dev/sda1
    mkfs.xfs -f -m reflink=1 -L backingfiles /dev/sda2
  fi

  BACKINGFILES_MOUNTPOINT="$1"
  MUTABLE_MOUNTPOINT="$2"
  if grep -q backingfiles /etc/fstab
  then
    log_progress "backingfiles already defined in /etc/fstab. Not modifying /etc/fstab."
  else
    echo "LABEL=backingfiles $BACKINGFILES_MOUNTPOINT xfs auto,rw,noatime 0 2" >> /etc/fstab
  fi
  if grep -q 'mutable' /etc/fstab
  then
    log_progress "mutable already defined in /etc/fstab. Not modifying /etc/fstab."
  else
    echo "LABEL=mutable $MUTABLE_MOUNTPOINT ext4 auto,rw 0 2" >> /etc/fstab
  fi
  log_progress "Done."
  exit 0
else
  echo "USB_DRIVE not set. Proceeding to SD card setup"
fi

# If partition 3 is the backingfiles partition, type xfs, and
# partition 4 the mutable partition, type ext4, then return early.
if [ /dev/disk/by-label/backingfiles -ef "${BOOT_DEVICE_PART}3" ] && \
    [ /dev/disk/by-label/mutable -ef "${BOOT_DEVICE_PART}4" ] && \
    blkid "${BOOT_DEVICE_PART}4" | grep -q 'TYPE="ext4"'
then
  if blkid "${BOOT_DEVICE_PART}3" | grep -q 'TYPE="xfs"'
  then
    # assume these were either created previously by the setup scripts,
    # or manually by the user, and that they're big enough
    log_progress "using existing backingfiles and mutable partitions"
    return &> /dev/null || exit 0
  elif blkid "${BOOT_DEVICE_PART}3" | grep -q 'TYPE="ext4"'
  then
    # special case: convert existing backingfiles from ext4 to xfs
    log_progress "reformatting existing backingfiles as xfs"
    killall archiveloop || true
    modprobe -r g_mass_storage
    if mount | grep -qw "/mnt/cam"
    then
      if ! umount /mnt/cam
      then
        log_progress "STOP: couldn't unmount /mnt/cam"
        exit 1
      fi
    fi
    if mount | grep -qw "/backingfiles"
    then
      if ! umount /backingfiles
      then
        log_progress "STOP: couldn't unmount /backingfiles"
        exit 1
      fi
    fi
    mkfs.xfs -f -m reflink=1 -L backingfiles "${BOOT_DEVICE_PART}3"

    # update /etc/fstab
    sed -i 's/LABEL=backingfiles .*/LABEL=backingfiles \/backingfiles xfs auto,rw,noatime 0 2/' /etc/fstab
    mount /backingfiles
    log_progress "backingfiles converted to xfs and mounted"
    return &> /dev/null || exit 0
  fi
fi

# partition 3 and 4 either don't exist, or are the wrong type
if [ -e "${BOOT_DEVICE_PART}3" ] || [ -e "${BOOT_DEVICE_PART}4" ]
then
  log_progress "STOP: partitions already exist, but are not as expected"
  log_progress "please delete them and re-run setup"
  exit 1
fi

BACKINGFILES_MOUNTPOINT="$1"
MUTABLE_MOUNTPOINT="$2"

log_progress "Checking existing partitions..."

DISK_SECTORS=$(blockdev --getsz "${BOOT_DEVICE}")
LAST_DISK_SECTOR=$((DISK_SECTORS - 1))
# mutable partition is 100MB at the end of the disk, calculate its start sector
FIRST_MUTABLE_SECTOR=$((LAST_DISK_SECTOR-204800+1))
# backingfiles partition sits between the root and mutable partition, calculate its start sector and size
LAST_ROOT_SECTOR=$(sfdisk -l "${BOOT_DEVICE}" | grep "${BOOT_DEVICE_PART}2" | awk '{print $3}')
FIRST_BACKINGFILES_SECTOR=$((LAST_ROOT_SECTOR + 1))
BACKINGFILES_NUM_SECTORS=$((FIRST_MUTABLE_SECTOR - FIRST_BACKINGFILES_SECTOR))

ORIGINAL_DISK_IDENTIFIER=$( fdisk -l "${BOOT_DEVICE}" | grep -e "^Disk identifier" | sed "s/Disk identifier: 0x//" )

log_progress "Modifying partition table for backing files partition..."
echo "$FIRST_BACKINGFILES_SECTOR,$BACKINGFILES_NUM_SECTORS" | sfdisk --force "${BOOT_DEVICE}" -N 3

log_progress "Modifying partition table for mutable (writable) partition for script usage..."
echo "$FIRST_MUTABLE_SECTOR," | sfdisk --force "${BOOT_DEVICE}" -N 4

# manually adding the partitions to the kernel's view of things is sometimes needed
if [ ! -e "${BOOT_DEVICE_PART}3" ] || [ ! -e "${BOOT_DEVICE_PART}4" ]
then
  partx --add --nr 3:4 "${BOOT_DEVICE}"
fi
if [ ! -e "${BOOT_DEVICE_PART}3" ] || [ ! -e "${BOOT_DEVICE_PART}4" ]
then
  log_progress "failed to add partitions"
  exit 1
fi

NEW_DISK_IDENTIFIER=$( fdisk -l "${BOOT_DEVICE}" | grep -e "^Disk identifier" | sed "s/Disk identifier: 0x//" )

log_progress "Writing updated partitions to fstab and /boot/cmdline.txt"
sed -i "s/${ORIGINAL_DISK_IDENTIFIER}/${NEW_DISK_IDENTIFIER}/g" /etc/fstab
sed -i "s/${ORIGINAL_DISK_IDENTIFIER}/${NEW_DISK_IDENTIFIER}/" /boot/cmdline.txt

log_progress "Formatting new partitions..."
# Force creation of filesystems even if previous filesystem appears to exist
mkfs.xfs -f -m reflink=1 -L backingfiles "${BOOT_DEVICE_PART}3"
mkfs.ext4 -F -L mutable "${BOOT_DEVICE_PART}4"

echo "LABEL=backingfiles $BACKINGFILES_MOUNTPOINT xfs auto,rw,noatime 0 2" >> /etc/fstab
echo "LABEL=mutable $MUTABLE_MOUNTPOINT ext4 auto,rw 0 2" >> /etc/fstab
