#!/bin/bash

# Adapted from https://github.com/adafruit/Raspberry-Pi-Installer-Scripts/blob/master/read-only-fs.sh

function log_progress () {
  if declare -F setup_progress > /dev/null
  then
    setup_progress "make-root-fs-readonly: $1"
    return
  fi
  echo "make-root-fs-readonly: $1"
}

log_progress "start"

function append_cmdline_txt_param() {
  local toAppend="$1"
  # Don't add the option if it is already added.
  # If the command line gets too long the pi won't boot.
  # Look for the option at the end ($) or in the middle
  # of the command line and surrounded by space (\s).
  if ! grep -P -q "\s${toAppend}(\$|\s)" /boot/cmdline.txt
  then
    sed -i "s/\'/ ${toAppend}/g" /boot/cmdline.txt >/dev/null
  fi
}

function remove_cmdline_txt_param() {
  sed -i "s/\(\s\)${1}\(\s\|$\)//" /boot/cmdline.txt > /dev/null
}

log_progress "Disabling unnecessary service..."
systemctl disable apt-daily.timer
systemctl disable apt-daily-upgrade.timer

log_progress "Removing unwanted packages..."
apt-get remove -y --force-yes --purge triggerhappy logrotate dphys-swapfile bluez alsa-utils
apt-get -y --force-yes autoremove --purge
# Replace log management with busybox (use logread if needed)
log_progress "Installing ntp and busybox-syslogd..."
apt-get -y --force-yes install ntp busybox-syslogd; dpkg --purge rsyslog

log_progress "Configuring system..."

# Add fsck.mode=auto, noswap and/or ro to end of /boot/cmdline.txt
# Remove the fastboot paramater because it makes fsck not run
remove_cmdline_txt_param fastboot
append_cmdline_txt_param fsck.mode=auto
append_cmdline_txt_param noswap
append_cmdline_txt_param ro

# set root and mutable max mount count to 1, so they're checked every boot
tune2fs -c 1 /dev/disk/by-label/rootfs || log_progress "tune2fs failed for rootfs"
tune2fs -c 1 /dev/disk/by-label/mutable || log_progress "tune2fs failed for mutable"

# we're not using swap, so delete the swap file for some extra space
rm -f /var/swap

# Move fake-hwclock.data to /mutable directory so it can be updated
if ! findmnt --mountpoint /mutable > /dev/null
then
  log_progress "Mounting the mutable partition..."
  mount /mutable
  log_progress "Mounted."
fi
if [ ! -e "/mutable/etc" ]
then
  mkdir -p /mutable/etc
fi

if [ ! -L "/etc/fake-hwclock.data" ] && [ -e "/etc/fake-hwclock.data" ]
then
  log_progress "Moving fake-hwclock data"
  mv /etc/fake-hwclock.data /mutable/etc/fake-hwclock.data
  ln -s /mutable/etc/fake-hwclock.data /etc/fake-hwclock.data
fi
# By default fake-hwclock is run during early boot, before /mutable
# has been mounted and so will fail. Delay running it until /mutable
# has been mounted.
if [ -e /lib/systemd/system/fake-hwclock.service ]
then
  sed -i 's/Before=.*/After=mutable.mount/' /lib/systemd/system/fake-hwclock.service
fi

# Create a configs directory for others to use
if [ ! -e "/mutable/configs" ]
then
  mkdir -p /mutable/configs
fi

# Move /var/spool to /tmp
if [ -L /var/spool ]
then
  log_progress "fixing /var/spool"
  rm /var/spool
  mkdir /var/spool
  chmod 755 /var/spool
  # a tmpfs fstab entry for /var/spool will be added below
else
  rm -rf /var/spool/*
fi

# Change spool permissions in var.conf (rondie/Margaret fix)
sed -i "s/spool\s*0755/spool 1777/g" /usr/lib/tmpfiles.d/var.conf >/dev/null

# Move dhcpd.resolv.conf to tmpfs
if [ ! -e /tmp/dhcpcd.resolv.conf ]
then
  mv /etc/resolv.conf /tmp/dhcpcd.resolv.conf
  ln -s /tmp/dhcpcd.resolv.conf /etc/resolv.conf
fi

# Update /etc/fstab
# make /boot read-only
# make / read-only
# tmpfs /var/log tmpfs nodev,nosuid 0 0
# tmpfs /var/tmp tmpfs nodev,nosuid 0 0
# tmpfs /tmp     tmpfs nodev,nosuid 0 0
if ! grep -P -q "/boot\s+vfat\s+.+?(?=,ro)" /etc/fstab
then
  sed -i -r "s@(/boot\s+vfat\s+\S+)@\1,ro@" /etc/fstab
fi

if ! grep -P -q "/\s+ext4\s+.+?(?=,ro)" /etc/fstab
then
  sed -i -r "s@(/\s+ext4\s+\S+)@\1,ro@" /etc/fstab
fi

if ! grep -w -q "/var/log" /etc/fstab
then
  echo "tmpfs /var/log tmpfs nodev,nosuid 0 0" >> /etc/fstab
fi

if ! grep -w -q "/var/tmp" /etc/fstab
then
  echo "tmpfs /var/tmp tmpfs nodev,nosuid 0 0" >> /etc/fstab
fi

if ! grep -w -q "/tmp" /etc/fstab
then
  echo "tmpfs /tmp    tmpfs nodev,nosuid 0 0" >> /etc/fstab
fi

if ! grep -w -q "/var/spool" /etc/fstab
then
  echo "tmpfs /var/spool tmpfs nodev,nosuid 0 0" >> /etc/fstab
fi

log_progress "done"
