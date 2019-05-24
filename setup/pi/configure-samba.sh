#!/bin/bash

SAMBA_GUEST=${SAMBA_GUEST:-false}

if [ "$SAMBA_GUEST" = "true" ]
then
  GUEST_OK="yes"
else
  GUEST_OK="no"
fi

if ! hash smbd &> /dev/null
then
  # before installing, move some of samba's folders off of the
  # soon-to-be-readonly root partition

  mkdir -p /var/cache/samba
  mkdir -p /var/run/samba

  if ! grep -q samba /etc/fstab
  then
    echo "tmpfs /var/run/samba tmpfs nodev,nosuid 0 0" >> /etc/fstab
    echo "tmpfs /var/cache/samba tmpfs nodev,nosuid 0 0" >> /etc/fstab
  fi

  mount /var/cache/samba
  mount /var/run/samba

  if [ -d /var/lib/samba ]
  then
    if ! findmnt --mountpoint /mutable
    then
        mount /mutable
    fi

    mkdir -p /mutable/varlib
    mv /var/lib/samba /mutable/varlib
    ln -s /mutable/varlib/samba /var/lib/samba
  fi

  # directory where the snapshots will be mounted and exported by samba
  if [ ! -e /mnt/smbexport ]
  then
    mkdir /mnt/smbexport
    echo "tmpfs /mnt/smbexport tmpfs nodev,nosuid 0 0" >> /etc/fstab
  fi

  # preinstall smb.conf so the service will come up with the
  # correct configuration
  cat <<- EOF > /etc/samba/smb.conf
	[global]
	   deadtime = 2
	   workgroup = WORKGROUP
	   dns proxy = no
	   log file = /var/log/samba.log.%m
	   max log size = 1000
	   syslog = 0
	   panic action = /usr/share/samba/panic-action %d
	   server role = standalone server
	   passdb backend = tdbsam
	   obey pam restrictions = yes
	   unix password sync = yes
	   passwd program = /usr/bin/passwd %u
	   passwd chat = *Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .
	   pam password change = yes
	   map to guest = bad user
	   usershare allow guests = yes

	[TeslaCam]
	   read only = yes
	   locking = no
	   path = /mnt/smbexport/%I-%d
	   guest ok = $GUEST_OK
	   create mask = 0775
	   veto files = /._*/.DS_Store/
	   delete veto files = yes
	   root preexec = /root/bin/smb-on.sh "%I-%d"
	   root postexec = /root/bin/smb-off.sh "%I-%d"
	EOF

  apt-get -y --force-yes install samba
  service smbd start
  echo -e "raspberry\nraspberry\n" | smbpasswd -s -a pi 
  service smbd stop
fi
