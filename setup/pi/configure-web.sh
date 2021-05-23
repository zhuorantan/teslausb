#!/bin/bash -eu

setup_progress "configuring nginx"

# delete existing nginx fstab entries
sed -i "/.*\/nginx tmpfs.*/d" /etc/fstab
# and recreate them
echo "tmpfs /var/log/nginx tmpfs nodev,nosuid 0 0" >> /etc/fstab
echo "tmpfs /var/lib/nginx tmpfs nodev,nosuid 0 0" >> /etc/fstab
# only needed for initial setup, since systemd will create these automatically after that
mkdir -p /var/log/nginx
mkdir -p /var/lib/nginx
mount /var/log/nginx
mount /var/lib/nginx

apt-get -y --force-yes install nginx fcgiwrap libnginx-mod-http-fancyindex libfuse-dev

# install data files and config files
systemctl stop nginx.service &> /dev/null || true
mkdir -p /var/www
umount /var/www/html/TeslaCam &> /dev/null || true
rm -rf /var/www/html
cp -r "$SOURCE_DIR/teslausb-www/html" /var/www/
ln -s /boot/teslausb-headless-setup.log /var/www/html/
ln -s /mutable/archiveloop.log /var/www/html/
ln -s /tmp/diagnostics.txt /var/www/html/
mkdir /var/www/html/TeslaCam
cp -rf "$SOURCE_DIR/teslausb-www/teslausb.nginx" /etc/nginx/sites-available
ln -sf /etc/nginx/sites-available/teslausb.nginx /etc/nginx/sites-enabled/default

# install the fuse layer needed to work around an incompatibility
# between Chrome and Tesla's recordings
g++ -o /root/cttseraser -D_FILE_OFFSET_BITS=64 "$SOURCE_DIR/teslausb-www/cttseraser.cpp" -lstdc++ -lfuse

cat > /sbin/mount.ctts << EOF
#!/bin/bash -eu
/root/cttseraser "\$@" -o allow_other
EOF
chmod +x /sbin/mount.ctts

sed -i '/mount.ctts/d' /etc/fstab
echo "mount.ctts#/mutable/TeslaCam /var/www/html/TeslaCam fuse defaults,nofail,x-systemd.requires=/mutable 0 0" >> /etc/fstab

sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf

# to get diagnostics and perform other teslausb functionality,
# nginx needs to be able to sudo
echo 'www-data ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/010_www-data-nopasswd
chmod 440 /etc/sudoers.d/010_www-data-nopasswd

setup_progress "done configuring nginx"
