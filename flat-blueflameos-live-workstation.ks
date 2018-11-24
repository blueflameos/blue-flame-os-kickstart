#version=DEVEL
# X Window System configuration information
xconfig  --startxonboot
# Keyboard layouts
keyboard 'us'
# Root password
rootpw --iscrypted --lock locked
# System language
lang en_US.UTF-8
# Shutdown after installation
shutdown
# System timezone
timezone US/Eastern
# Network information
network  --bootproto=dhcp --device=link --activate
repo --name="fedora" --mirrorlist=https://mirrors.fedoraproject.org/mirrorlist?repo=fedora-$releasever&arch=$basearch
repo --name="updates" --mirrorlist=https://mirrors.fedoraproject.org/mirrorlist?repo=updates-released-f$releasever&arch=$basearch

#blueflameos
repo --name="adobe"   --baseurl=http://linuxdownload.adobe.com/linux/x86_64/
repo --name="rpmfusion-free"      --baseurl=http://download1.rpmfusion.org/free/fedora/releases/$releasever/Everything/$basearch/os/
repo --name="rpmfusion-none-free" --baseurl=http://download1.rpmfusion.org/nonfree/fedora/releases/$releasever/Everything/$basearch/os/
repo --name="google-chrome" --baseurl=http://dl.google.com/linux/chrome/rpm/stable/x86_64
repo --name="blueflameos"   --baseurl=https://copr-be.cloud.fedoraproject.org/results/youssefmsourani/BlueFlameOS/fedora-$releasever-$basearch/
repo --name="luniversalinstaller"      --baseurl=https://copr-be.cloud.fedoraproject.org/results/youssefmsourani/luniversalinstaller/fedora-$releasever-$basearch/
repo --name="arfedora-control-center" --baseurl=https://copr-be.cloud.fedoraproject.org/results/youssefmsourani/arcontrolcenter/fedora-$releasever-$basearch/
repo --name="sgvrecord" --baseurl=https://copr-be.cloud.fedoraproject.org/results/youssefmsourani/sgvrecord/fedora-$releasever-$basearch/
repo --name="st-strans" --baseurl=https://copr-be.cloud.fedoraproject.org/results/youssefmsourani/st-trans/fedora-$releasever-$basearch/
repo --cost=1 --name="local-repo"    --baseurl=http://192.168.1.71:8080/
#blueflameos

# Use network installation
url --mirrorlist="https://mirrors.fedoraproject.org/mirrorlist?repo=fedora-$releasever&arch=$basearch"
# System authorization information
auth --useshadow --passalgo=sha512
# Firewall configuration
firewall --enabled --service=mdns
# SELinux configuration
selinux --enforcing

# System services
services --disabled="sshd" --enabled="NetworkManager,ModemManager"
# System bootloader configuration
bootloader --location=none
# Clear the Master Boot Record
zerombr
# Partition clearing information
clearpart --all
# Disk partitioning information
part / --fstype="ext4" --size=5120
part / --size=6656

#blueflameos
part / --size=8192
#blueflameos

%post
# FIXME: it'd be better to get this installed from a package
cat > /etc/rc.d/init.d/livesys << EOF
#!/bin/bash
#
# live: Init script for live image
#
# chkconfig: 345 00 99
# description: Init script for live image.
### BEGIN INIT INFO
# X-Start-Before: display-manager chronyd
### END INIT INFO

. /etc/init.d/functions

if ! strstr "\`cat /proc/cmdline\`" rd.live.image || [ "\$1" != "start" ]; then
    exit 0
fi

if [ -e /.liveimg-configured ] ; then
    configdone=1
fi

exists() {
    which \$1 >/dev/null 2>&1 || return
    \$*
}

livedir="LiveOS"
for arg in \`cat /proc/cmdline\` ; do
  if [ "\${arg##rd.live.dir=}" != "\${arg}" ]; then
    livedir=\${arg##rd.live.dir=}
    continue
  fi
  if [ "\${arg##live_dir=}" != "\${arg}" ]; then
    livedir=\${arg##live_dir=}
  fi
done

# enable swaps unless requested otherwise
swaps=\`blkid -t TYPE=swap -o device\`
if ! strstr "\`cat /proc/cmdline\`" noswap && [ -n "\$swaps" ] ; then
  for s in \$swaps ; do
    action "Enabling swap partition \$s" swapon \$s
  done
fi
if ! strstr "\`cat /proc/cmdline\`" noswap && [ -f /run/initramfs/live/\${livedir}/swap.img ] ; then
  action "Enabling swap file" swapon /run/initramfs/live/\${livedir}/swap.img
fi

mountPersistentHome() {
  # support label/uuid
  if [ "\${homedev##LABEL=}" != "\${homedev}" -o "\${homedev##UUID=}" != "\${homedev}" ]; then
    homedev=\`/sbin/blkid -o device -t "\$homedev"\`
  fi

  # if we're given a file rather than a blockdev, loopback it
  if [ "\${homedev##mtd}" != "\${homedev}" ]; then
    # mtd devs don't have a block device but get magic-mounted with -t jffs2
    mountopts="-t jffs2"
  elif [ ! -b "\$homedev" ]; then
    loopdev=\`losetup -f\`
    if [ "\${homedev##/run/initramfs/live}" != "\${homedev}" ]; then
      action "Remounting live store r/w" mount -o remount,rw /run/initramfs/live
    fi
    losetup \$loopdev \$homedev
    homedev=\$loopdev
  fi

  # if it's encrypted, we need to unlock it
  if [ "\$(/sbin/blkid -s TYPE -o value \$homedev 2>/dev/null)" = "crypto_LUKS" ]; then
    echo
    echo "Setting up encrypted /home device"
    plymouth ask-for-password --command="cryptsetup luksOpen \$homedev EncHome"
    homedev=/dev/mapper/EncHome
  fi

  # and finally do the mount
  mount \$mountopts \$homedev /home
  # if we have /home under what's passed for persistent home, then
  # we should make that the real /home.  useful for mtd device on olpc
  if [ -d /home/home ]; then mount --bind /home/home /home ; fi
  [ -x /sbin/restorecon ] && /sbin/restorecon /home
  if [ -d /home/liveuser ]; then USERADDARGS="-M" ; fi
}

findPersistentHome() {
  for arg in \`cat /proc/cmdline\` ; do
    if [ "\${arg##persistenthome=}" != "\${arg}" ]; then
      homedev=\${arg##persistenthome=}
    fi
  done
}

if strstr "\`cat /proc/cmdline\`" persistenthome= ; then
  findPersistentHome
elif [ -e /run/initramfs/live/\${livedir}/home.img ]; then
  homedev=/run/initramfs/live/\${livedir}/home.img
fi

# if we have a persistent /home, then we want to go ahead and mount it
if ! strstr "\`cat /proc/cmdline\`" nopersistenthome && [ -n "\$homedev" ] ; then
  action "Mounting persistent /home" mountPersistentHome
fi

if [ -n "\$configdone" ]; then
  exit 0
fi

# add liveuser user with no passwd
action "Adding live user" useradd \$USERADDARGS -c "Live System User" liveuser
passwd -d liveuser > /dev/null
usermod -aG wheel liveuser > /dev/null

# Remove root password lock
passwd -d root > /dev/null

# turn off firstboot for livecd boots
systemctl --no-reload disable firstboot-text.service 2> /dev/null || :
systemctl --no-reload disable firstboot-graphical.service 2> /dev/null || :
systemctl stop firstboot-text.service 2> /dev/null || :
systemctl stop firstboot-graphical.service 2> /dev/null || :

# don't use prelink on a running live image
sed -i 's/PRELINKING=yes/PRELINKING=no/' /etc/sysconfig/prelink &>/dev/null || :

# turn off mdmonitor by default
systemctl --no-reload disable mdmonitor.service 2> /dev/null || :
systemctl --no-reload disable mdmonitor-takeover.service 2> /dev/null || :
systemctl stop mdmonitor.service 2> /dev/null || :
systemctl stop mdmonitor-takeover.service 2> /dev/null || :

# don't enable the gnome-settings-daemon packagekit plugin
gsettings set org.gnome.software download-updates 'false' || :

# don't start cron/at as they tend to spawn things which are
# disk intensive that are painful on a live image
systemctl --no-reload disable crond.service 2> /dev/null || :
systemctl --no-reload disable atd.service 2> /dev/null || :
systemctl stop crond.service 2> /dev/null || :
systemctl stop atd.service 2> /dev/null || :

# turn off abrtd on a live image
systemctl --no-reload disable abrtd.service 2> /dev/null || :
systemctl stop abrtd.service 2> /dev/null || :

# Don't sync the system clock when running live (RHBZ #1018162)
sed -i 's/rtcsync//' /etc/chrony.conf

# Mark things as configured
touch /.liveimg-configured

# add static hostname to work around xauth bug
# https://bugzilla.redhat.com/show_bug.cgi?id=679486
# the hostname must be something else than 'localhost'
# https://bugzilla.redhat.com/show_bug.cgi?id=1370222
echo "localhost-live" > /etc/hostname

EOF

# bah, hal starts way too late
cat > /etc/rc.d/init.d/livesys-late << EOF
#!/bin/bash
#
# live: Late init script for live image
#
# chkconfig: 345 99 01
# description: Late init script for live image.

. /etc/init.d/functions

if ! strstr "\`cat /proc/cmdline\`" rd.live.image || [ "\$1" != "start" ] || [ -e /.liveimg-late-configured ] ; then
    exit 0
fi

exists() {
    which \$1 >/dev/null 2>&1 || return
    \$*
}

touch /.liveimg-late-configured

# read some variables out of /proc/cmdline
for o in \`cat /proc/cmdline\` ; do
    case \$o in
    ks=*)
        ks="--kickstart=\${o#ks=}"
        ;;
    xdriver=*)
        xdriver="\${o#xdriver=}"
        ;;
    esac
done

# if liveinst or textinst is given, start anaconda
if strstr "\`cat /proc/cmdline\`" liveinst ; then
   plymouth --quit
   /usr/sbin/liveinst \$ks
fi
if strstr "\`cat /proc/cmdline\`" textinst ; then
   plymouth --quit
   /usr/sbin/liveinst --text \$ks
fi

# configure X, allowing user to override xdriver
if [ -n "\$xdriver" ]; then
   cat > /etc/X11/xorg.conf.d/00-xdriver.conf <<FOE
Section "Device"
	Identifier	"Videocard0"
	Driver	"\$xdriver"
EndSection
FOE
fi

EOF

chmod 755 /etc/rc.d/init.d/livesys
/sbin/restorecon /etc/rc.d/init.d/livesys
/sbin/chkconfig --add livesys

chmod 755 /etc/rc.d/init.d/livesys-late
/sbin/restorecon /etc/rc.d/init.d/livesys-late
/sbin/chkconfig --add livesys-late

# enable tmpfs for /tmp
systemctl enable tmp.mount

# make it so that we don't do writing to the overlay for things which
# are just tmpdirs/caches
# note https://bugzilla.redhat.com/show_bug.cgi?id=1135475
cat >> /etc/fstab << EOF
vartmp   /var/tmp    tmpfs   defaults   0  0
EOF

# work around for poor key import UI in PackageKit
rm -f /var/lib/rpm/__db*
releasever=$(rpm -q --qf '%{version}\n' --whatprovides system-release)
basearch=$(uname -i)
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-$releasever-$basearch
echo "Packages within this LiveCD"
rpm -qa
# Note that running rpm recreates the rpm db files which aren't needed or wanted
rm -f /var/lib/rpm/__db*

# go ahead and pre-make the man -k cache (#455968)
/usr/bin/mandb

# make sure there aren't core files lying around
rm -f /core*

# remove random seed, the newly installed instance should make it's own
rm -f /var/lib/systemd/random-seed

# convince readahead not to collect
# FIXME: for systemd

echo 'File created by kickstart. See systemd-update-done.service(8).' \
    | tee /etc/.updated >/var/.updated

# Drop the rescue kernel and initramfs, we don't need them on the live media itself.
# See bug 1317709
rm -f /boot/*-rescue*

# Disable network service here, as doing it in the services line
# fails due to RHBZ #1369794
/sbin/chkconfig network off

# Remove machine-id on pre generated images
rm -f /etc/machine-id
touch /etc/machine-id

%end

%post --nochroot
cp $INSTALL_ROOT/usr/share/licenses/*-release/* $LIVE_ROOT/

# only works on x86, x86_64
if [ "$(uname -i)" = "i386" -o "$(uname -i)" = "x86_64" ]; then
    # For livecd-creator builds
    if [ ! -d $LIVE_ROOT/LiveOS ]; then mkdir -p $LIVE_ROOT/LiveOS ; fi
    cp /usr/bin/livecd-iso-to-disk $LIVE_ROOT/LiveOS

    # For lorax/livemedia-creator builds
    sed -i '
    /## make boot.iso/ i\
    # Add livecd-iso-to-disk script to .iso filesystem at /LiveOS/\
    <% f = "usr/bin/livecd-iso-to-disk" %>\
    %if exists(f):\
        install ${f} ${LIVEDIR}/${f|basename}\
    %endif\
    ' /usr/share/lorax/templates.d/99-generic/live/x86.tmpl
fi

%end

%post

cat >> /etc/rc.d/init.d/livesys << EOF


# disable gnome-software automatically downloading updates
cat >> /usr/share/glib-2.0/schemas/org.gnome.software.gschema.override << FOE
[org.gnome.software]
download-updates=false
FOE

# don't autostart gnome-software session service
rm -f /etc/xdg/autostart/gnome-software-service.desktop

# disable the gnome-software shell search provider
cat >> /usr/share/gnome-shell/search-providers/org.gnome.Software-search-provider.ini << FOE
DefaultDisabled=true
FOE

# don't run gnome-initial-setup
mkdir ~liveuser/.config
touch ~liveuser/.config/gnome-initial-setup-done

# suppress anaconda spokes redundant with gnome-initial-setup
cat >> /etc/sysconfig/anaconda << FOE
[NetworkSpoke]
visited=1

[PasswordSpoke]
visited=1

[UserSpoke]
visited=1
FOE

# make the installer show up
if [ -f /usr/share/applications/liveinst.desktop ]; then
  # Show harddisk install in shell dash
  sed -i -e 's/NoDisplay=true/NoDisplay=false/' /usr/share/applications/liveinst.desktop ""
  # need to move it to anaconda.desktop to make shell happy
  mv /usr/share/applications/liveinst.desktop /usr/share/applications/anaconda.desktop

  cat >> /usr/share/glib-2.0/schemas/org.gnome.shell.gschema.override << FOE
[org.gnome.shell]
favorite-apps=['firefox.desktop', 'google-chrome.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'rhythmbox.desktop', 'org.gnome.Software.desktop', 'org.gnome.gedit.desktop', 'org.github.yucefsourani.ArControlCenter.desktop','org.gnome.Screenshot.desktop']
FOE

  # Make the welcome screen show up
  if [ -f /usr/share/anaconda/gnome/fedora-welcome.desktop ]; then
    mkdir -p ~liveuser/.config/autostart
    cp /usr/share/anaconda/gnome/fedora-welcome.desktop /usr/share/applications/
    cp /usr/share/anaconda/gnome/fedora-welcome.desktop ~liveuser/.config/autostart/
  fi

  # Copy Anaconda branding in place
  if [ -d /usr/share/lorax/product/usr/share/anaconda ]; then
    cp -a /usr/share/lorax/product/* /
  fi
fi

# rebuild schema cache with any overrides we installed
glib-compile-schemas /usr/share/glib-2.0/schemas

# set up auto-login
cat > /etc/gdm/custom.conf << FOE
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=liveuser
FOE

# Turn off PackageKit-command-not-found while uninstalled
if [ -f /etc/PackageKit/CommandNotFound.conf ]; then
  sed -i -e 's/^SoftwareSourceSearch=true/SoftwareSourceSearch=false/' /etc/PackageKit/CommandNotFound.conf
fi

# make sure to set the right permissions and selinux contexts
chown -R liveuser:liveuser /home/liveuser/
restorecon -R /home/liveuser/

EOF

#blueflameos
/usr/bin/mkdir -p $INSTALL_ROOT/etc/skel/.mozilla/firefox/blueflameos.default
/usr/bin/cp mozilla/firefox/profiles.ini $INSTALL_ROOT/etc/skel/.mozilla/firefox/
/usr/bin/cp mozilla/firefox/blueflameos.default/prefs.js $INSTALL_ROOT/etc/skel/.mozilla/firefox/blueflameos.default

/usr/bin/firewall-cmd --add-service=kde-connect --permanent 2> /dev/null || :
#blueflameos

%end

%packages
@anaconda-tools
@base-x
@core
@firefox
@fonts
@gnome-desktop
@guest-desktop-agents
@hardware-support
@libreoffice
@multimedia
@networkmanager-submodules
@printing
@workstation-product
aajohan-comfortaa-fonts
anaconda
anaconda-install-env-deps
dracut-live
glibc-all-langpacks
kernel
kernel-modules
kernel-modules-extra
memtest86+
syslinux
-@dial-up
-@input-methods
-@standard
-gfs2-utils
-reiserfs-utils

#blueflameos
-fedora-release
-fedora-logos
-fedora-logos-httpd
-fedora-bookmarks
-fedora-release-workstation
-fedora-release-notes

blue-flame-os-custom-workstation
blue-flame-os-repos
blue-flame-os-release
blue-flame-os-logos
blue-flame-os-logos-httpd
blue-flame-os-bookmarks
blue-flame-os-release-workstation
blue-flame-os-release-notes
st-trans
luniversalinstaller
arfedora-control-center
sgvrecord
libwnck3

breeze-cursor-theme
McOS-MJV-3.30-theme
MacOSX-Gnome-Light-theme 
firewatch-2016-game-wallpaper
la-capitaine-icon-theme 
gnome-shell-extension-user-theme
gnome-shell-extension-drive-menu

gnome-shell-extension-clipboard-indicator
gnome-shell-extension-CoverflowAltTab
#gnome-shell-extension-arabiclangrun
gnome-shell-extension-sound-output-device-chooser
gnome-shell-extension-dash-to-dock
gnome-shell-extension-unlockDialogBackground
gnome-shell-extension-netspeed
gnome-shell-extension-blyr
gnome-shell-extension-TopIcons
gnome-shell-extension-gTile
#gnome-shell-extension-mconnect


rpmfusion-free-release
rpmfusion-nonfree-release
adobe-release
flash-plugin
xterm
geany
geany-themes
google-chrome-stable
fedora-workstation-repositories
kde-connect
vlc
xine-lib
amrnb
gstreamer-plugins-good
lame-libs
libdvdnav
gstreamer-plugin-crystalhd
gstreamer1-plugins-bad-free-extras
gstreamer1-plugins-bad-nonfree
gstreamer1-plugins-good
gstreamer1-vaapi
amrwb
lame
gstreamer1-plugins-good-extras
gstreamer1-plugins-bad-free
gstreamer-plugins-bad-free
gstreamer1-plugins-bad-freeworld
libdvdread
gstreamer-ffmpeg
gstreamer-rtsp
gstreamer-plugins-espeak
gstreamer-plugins-bad-free-extras
flac
ffmpeg-libs
lsdvd
gstreamer-plugins-fc
gstreamer1-libav
ffmpeg
faad2
gstreamer-plugins-ugly
xine-lib-extras
gstreamer1-plugins-ugly
gstreamer-plugins-bad-nonfree
gstreamer-plugins-bad
compat-ffmpeg28
xine-lib-devel
x264
bicon
dconf-editor
nm-connection-editor
gnome-terminal-nautilus
gnome-tweak-tool
gvfs-mtp
simple-mtpfs
transmission
chrome-gnome-shell
nano
#blueflameos

%end
