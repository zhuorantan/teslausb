#!/bin/bash -eu

setup_progress "configuring nginx"

if ! grep nginx /etc/fstab
then
  echo "tmpfs /var/log/nginx tmpfs nodev,nosuid 0 0" >> /etc/fstab
  mkdir -p /var/log/nginx # only needed for initial setup, since systemd will create it automatically after that
  mount /var/log/nginx
fi

apt-get -y --force-yes install nginx fcgiwrap

# install data files and config files
mkdir -p /var/www
rm -rf /var/www/html
cp -r "$SOURCE_DIR/teslausb-www/html" /var/www/
ln -s /boot/teslausb-headless-setup.log /var/www/html/
ln -s /mutable/archiveloop.log /var/www/html/
ln -s /tmp/diagnostics.txt /var/www/html/
cp -rf "$SOURCE_DIR/teslausb-www/teslausb.nginx" /etc/nginx/sites-available
ln -sf /etc/nginx/sites-available/teslausb.nginx /etc/nginx/sites-enabled/default

# to get diagnostics and perform other teslausb functionality,
# nginx needs to be able to sudo
echo 'www-data ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/010_www-data-nopasswd
chmod 440 /etc/sudoers.d/010_www-data-nopasswd

setup_progress "done configuring nginx"
