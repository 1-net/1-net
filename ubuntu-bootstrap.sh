#!/bin/bash

if [[ $EUID -eq 0 ]]; then
    echo "Please run this script as normal user"; exit 1
fi

## sudo keepalive
sudo -v; while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

## Put the packages you want to install in the array below
packages=(apt-transport-https vim curl p7zip-full caffeine gufw gnome-tweaks gnome-shell-extension-manager ubuntu-restricted-extras mpv sublime-text google-chrome-stable)
# insync is removed due to repo errors

## Set proxy server for apt
sudo tee <<EOF /etc/apt/apt.conf >/dev/null
Acquire::http::proxy "socks5h://192.168.5.1:1080";
Acquire::https::proxy "socks5h://192.168.5.1:1080";
EOF

## Remove snaps
if dpkg --get-selections | awk '{ print $1 }' | grep -qx "snapd"; then 
    echo "Removing snap applications..."
    sudo snap remove "$(snap list | awk '!/^Name|^core|^snapd/ {print $1}')"
    sudo snap remove core && sudo snap remove snapd
    sudo systemctl stop snapd
    sudo apt -yqq purge snapd
    sudo apt-mark hold snapd
    rm -rf ~/snap
    sudo rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd
fi

## Set up software repositories

if printf '%s\0' "${packages[@]}" | grep -Fxqz 'insync'; then
    GPGKEY=/etc/apt/trusted.gpg.d/insync.gpg
    REPOFILE=/etc/apt/sources.list.d/insync.list
    if [ ! -f "$GPGKEY" ]; then sudo gpg --no-default-keyring --keyring $GPGKEY --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys ACCAF35C;fi
    if [ ! -f "$REPOFILE" ]; then echo "deb http://apt.insync.io/ubuntu $(lsb_release -sc) non-free contrib" | sudo tee $REPOFILE >/dev/null; fi
fi

if printf '%s\0' "${packages[@]}" | grep -Fxqz 'sublime-text'; then
    GPGKEY=/etc/apt/trusted.gpg.d/sublimehq.gpg
    REPOFILE=/etc/apt/sources.list.d/sublime-text.list
    if [ ! -f "$GPGKEY" ]; then wget -O - https://download.sublimetext.com/sublimehq-pub.gpg | sudo gpg --dearmor -o $GPGKEY; fi
    if [ ! -f "$REPOFILE" ]; then echo 'deb https://download.sublimetext.com/ apt/stable/' | sudo tee $REPOFILE >/dev/null; fi
fi

if printf '%s\0' "${packages[@]}" | grep -Fxqz 'google-chrome-stable'; then
    GPGKEY=/etc/apt/trusted.gpg.d/google-chrome.gpg
    REPOFILE=/etc/apt/sources.list.d/google-chrome.list
    if [ ! -f "$GPGKEY" ]; then wget -O - https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o $GPGKEY; fi
    if [ ! -f "$REPOFILE" ]; then echo 'deb [arch=amd64] https://dl.google.com/linux/chrome/deb/ stable main' | sudo tee $REPOFILE >/dev/null; fi
fi

## "Updating repositories"
if { sudo apt -q update 2>&1 || echo E: update failed; } | grep -q '^[WE]:'; then
    echo "Failed to fetch some repositories, exiting..."; exit 1
else
    sudo apt -yqq full-upgrade
fi

## "Installing packages"
for i in "${packages[@]}"; do 
    dpkg --get-selections | awk '{ print $1 }' | grep -qx "$i" || sudo apt -yqq install "$i"
done

## Set default editor to vim; remove gedit if sublime text is installed
if [ -f /usr/bin/vim.basic ]; then sudo update-alternatives --set editor /usr/bin/vim.basic; fi
dpkg --get-selections | awk '{ print $1 }' | grep -qx "sublime-text" && sudo apt -yqq purge gedit

## Apply UI changes
if grep -qx "1" /sys/class/power_supply/BAT*/present; then gsettings set org.gnome.desktop.interface show-battery-percentage true; fi
gsettings set org.gnome.shell.overrides attach-modal-dialogs false
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gnome-extensions disable ding@rastersoft.com
gnome-extensions disable ubuntu-dock@ubuntu.com

## Apply firewall settings
sudo ufw default deny incoming
sudo ufw default allow outgoing
dpkg --get-selections | awk '{ print $1 }' | grep -qx "openssh-server" && sudo ufw allow OpenSSH
sudo ufw --force enable
