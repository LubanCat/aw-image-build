#!/bin/bash
#
# Copyright (c) 2013-2021 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.


# Functions:

# install_common
# install_rclocal
# install_distribution_specific
# post_debootstrap_tweaks


# install_common
#
install_common()
{
	display_alert "Applying common tweaks" "" "info"

	# add dummy fstab entry to make mkinitramfs happy
	echo "/dev/mmcblk0p1 / $ROOTFS_TYPE defaults 0 1" >> "${SDCARD}"/etc/fstab
	# required for initramfs-tools-core on Stretch since it ignores the / fstab entry
	echo "/dev/mmcblk0p2 /usr $ROOTFS_TYPE defaults 0 2" >> "${SDCARD}"/etc/fstab

	# create modules file
	local modules=MODULES_${BRANCH^^}
	if [[ -n "${!modules}" ]]; then
		tr ' ' '\n' <<< "${!modules}" > "${SDCARD}"/etc/modules
	elif [[ -n "${MODULES}" ]]; then
		tr ' ' '\n' <<< "${MODULES}" > "${SDCARD}"/etc/modules
	fi

	# create blacklist files
	local blacklist=MODULES_BLACKLIST_${BRANCH^^}
	if [[ -n "${!blacklist}" ]]; then
		tr ' ' '\n' <<< "${!blacklist}" | sed -e 's/^/blacklist /' > "${SDCARD}/etc/modprobe.d/blacklist-${BOARD}.conf"
	elif [[ -n "${MODULES_BLACKLIST}" ]]; then
		tr ' ' '\n' <<< "${MODULES_BLACKLIST}" | sed -e 's/^/blacklist /' > "${SDCARD}/etc/modprobe.d/blacklist-${BOARD}.conf"
	fi

	# configure MIN / MAX speed for cpufrequtils
	cat <<-EOF > "${SDCARD}"/etc/default/cpufrequtils
	ENABLE=true
	MIN_SPEED=$CPUMIN
	MAX_SPEED=$CPUMAX
	GOVERNOR=$GOVERNOR
	EOF

	# remove default interfaces file if present
	# before installing board support package
	rm -f "${SDCARD}"/etc/network/interfaces

	# disable selinux by default
	mkdir -p "${SDCARD}"/selinux
	[[ -f "${SDCARD}"/etc/selinux/config ]] && sed "s/^SELINUX=.*/SELINUX=disabled/" -i "${SDCARD}"/etc/selinux/config

	# remove Ubuntu's legal text
	[[ -f "${SDCARD}"/etc/legal ]] && rm "${SDCARD}"/etc/legal

	# Prevent loading paralel printer port drivers which we don't need here.
	# Suppress boot error if kernel modules are absent
	if [[ -f "${SDCARD}"/etc/modules-load.d/cups-filters.conf ]]; then
		sed "s/^lp/#lp/" -i "${SDCARD}"/etc/modules-load.d/cups-filters.conf
		sed "s/^ppdev/#ppdev/" -i "${SDCARD}"/etc/modules-load.d/cups-filters.conf
		sed "s/^parport_pc/#parport_pc/" -i "${SDCARD}"/etc/modules-load.d/cups-filters.conf
	fi

	# console fix due to Debian bug
	sed -e 's/CHARMAP=".*"/CHARMAP="'$CONSOLE_CHAR'"/g' -i "${SDCARD}"/etc/default/console-setup

	# add the /dev/urandom path to the rng config file
	echo "HRNGDEVICE=/dev/urandom" >> "${SDCARD}"/etc/default/rng-tools

	# ping needs privileged action to be able to create raw network socket
	# this is working properly but not with (at least) Debian Buster
	chroot "${SDCARD}" /bin/bash -c "chmod u+s /bin/ping"

	# change time zone data
	echo "${TZDATA}" > "${SDCARD}"/etc/timezone
	ln -sf /usr/share/zoneinfo/Asia/Shanghai "${SDCARD}"/etc/localtime

	# set root password
	chroot "${SDCARD}" /bin/bash -c "(echo $ROOTPWD;echo $ROOTPWD;) | passwd root >/dev/null 2>&1"

	# change console welcome text
	echo -e "[username:password] root:$ROOTPWD $USERNAME:$PASSWORD \n" >> "${SDCARD}"/etc/issue
	echo -e "Modify information : /etc/issue \n" >> "${SDCARD}"/etc/issue

	echo -e "[username:password] root:$ROOTPWD $USERNAME:$PASSWORD \n" >> "${SDCARD}"/etc/issue.net
	echo -e "Modify information : /etc/issue \n" >> "${SDCARD}"/etc/issue.net

	# enable few bash aliases enabled in Ubuntu by default to make it even
	sed "s/#alias ll='ls -l'/alias ll='ls -l'/" -i "${SDCARD}"/etc/skel/.bashrc
	sed "s/#alias la='ls -A'/alias la='ls -A'/" -i "${SDCARD}"/etc/skel/.bashrc
	sed "s/#alias l='ls -CF'/alias l='ls -CF'/" -i "${SDCARD}"/etc/skel/.bashrc
	# root user is already there. Copy bashrc there as well
	cp -v "${SDCARD}"/etc/skel/.bashrc "${SDCARD}"/root

	# display welcome message at first root login
	touch "${SDCARD}"/root/.not_logged_in_yet

	# initial date for fake-hwclock
	date -u '+%Y-%m-%d %H:%M:%S' > "${SDCARD}"/etc/fake-hwclock.data

	echo "${HOST_NAME}" > "${SDCARD}"/etc/hostname

	# set hostname in hosts file
	cat <<-EOF > "${SDCARD}"/etc/hosts
	127.0.0.1   localhost
	127.0.1.1   $HOST_NAME
	::1         localhost $HOST_NAME ip6-localhost ip6-loopback
	fe00::0     ip6-localnet
	ff00::0     ip6-mcastprefix
	ff02::1     ip6-allnodes
	ff02::2     ip6-allrouters
	EOF

	cd $TOP_DIR

	display_alert "Updating" "package lists"
	chroot "${SDCARD}" /bin/bash -c "apt-get update"

	display_alert "Temporarily disabling" "initramfs-tools hook for kernel"
	chroot "${SDCARD}" /bin/bash -c "chmod -v -x /etc/kernel/postinst.d/initramfs-tools"

	# install family packages
	if [[ -n ${PACKAGE_LIST_FAMILY} ]]; then
		display_alert "Installing PACKAGE_LIST_FAMILY packages" "${PACKAGE_LIST_FAMILY}"
		chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive  apt-get -yqq --no-install-recommends install $PACKAGE_LIST_FAMILY"
	fi

	# install board packages
	if [[ -n ${PACKAGE_LIST_BOARD} ]]; then
		display_alert "Installing PACKAGE_LIST_BOARD packages" "${PACKAGE_LIST_BOARD}"
		chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive  apt-get -yqq --no-install-recommends install $PACKAGE_LIST_BOARD"  || { display_alert "Failed to install PACKAGE_LIST_BOARD" "${PACKAGE_LIST_BOARD}" "err"; exit 2; }
	fi

	# remove family packages
	if [[ -n ${PACKAGE_LIST_FAMILY_REMOVE} ]]; then
		display_alert "Removing PACKAGE_LIST_FAMILY_REMOVE packages" "${PACKAGE_LIST_FAMILY_REMOVE}"
		chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive  apt-get -yqq remove --auto-remove $PACKAGE_LIST_FAMILY_REMOVE"
	fi

	# remove board packages
	if [[ -n ${PACKAGE_LIST_BOARD_REMOVE} ]]; then
		display_alert "Removing PACKAGE_LIST_BOARD_REMOVE packages" "${PACKAGE_LIST_BOARD_REMOVE}"
		for PKG_REMOVE in ${PACKAGE_LIST_BOARD_REMOVE}; do
			chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -yqq remove --auto-remove ${PKG_REMOVE}"
		done
	fi

	# install u-boot
	# @TODO: add install_bootloader() extension method, refactor into u-boot extension
	[[ "${UBOOT_CONFIG}" != "none" ]] && {
		install_deb_chroot "${DEB_DIR}/u-boot/${UBOOT_DEB}_${REVISION}_${ARCH}.deb"
	}

	# install kernel
	[[ -n $LINUX_SOURCE ]] && {

		install_deb_chroot "${DEB_DIR}/kernel/${KERNEL_DEB}_${REVISION}_${ARCH}.deb"
		install_deb_chroot "${DEB_DIR}/kernel/${KERNEL_DEB/image/headers}_${REVISION}_${ARCH}.deb"

		display_alert "apt-mark hold kernel packages" "${KERNEL_DEB} ${KERNEL_DEB/image/headers}" "info"
		chroot "${SDCARD}" /bin/bash -c "apt-mark hold ${KERNEL_DEB} ${KERNEL_DEB/image/headers} ${UBOOT_DEB}"
	}

	# install board support packages
	install_deb_chroot "${DEB_DIR}/$RELEASE/${BSP_SERVER_DEB_FULLNAME}.deb"

	# install lbc-desktop
	if [[ $BUILD_OS_TYPE == desktop ]]; then
		install_deb_chroot "${DEB_DIR}/${RELEASE}/${CHOSEN_DESKTOP}_${REVISION}_all.deb"
		# install_deb_chroot "${DEB_DIR}/${RELEASE}/${BSP_DESKTOP_PACKAGE_FULLNAME}.deb"
		# install display manager and PACKAGE_LIST_DESKTOP_FULL packages if enabled per board

		# update packages index
		chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get update"

		# install per family packages
		if [[ -n ${PACKAGE_LIST_DESKTOP_FAMILY} ]]; then
			chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -yqq --no-install-recommends install $PACKAGE_LIST_DESKTOP_FAMILY"
		fi

		if [[ -d ${SDCARD}/etc/lightdm ]]; then
			mkdir -p ${SDCARD}/etc/lightdm/lightdm.conf.d
			cat <<-EOF > ${SDCARD}/etc/lightdm/lightdm.conf.d/22-autologin.conf
			[Seat:*]
			autologin-user=$USERNAME
			autologin-user-timeout=0
			user-session=xfce
			EOF
		fi
	fi

	LBC_FIRMWARE_VER=$(cat ${DEB_DIR}/lbc-firmware/DEBIAN/control | grep Version | awk '{print $2}')
	# install lbc-firmware
	install_deb_chroot "${DEB_DIR}/lbc-firmware_${LBC_FIRMWARE_VER}_all.deb"

	# add user
	chroot "${SDCARD}" /bin/bash -c "adduser --quiet --disabled-password --shell /bin/bash --home /home/${USERNAME} --gecos ${USERNAME} ${USERNAME}"
	chroot "${SDCARD}" /bin/bash -c "(echo ${PASSWORD};echo ${PASSWORD};) | passwd "${USERNAME}" >/dev/null 2>&1"
	for additionalgroup in sudo netdev audio video disk tty users games dialout plugdev input bluetooth systemd-journal ssh; do
	    chroot "${SDCARD}" /bin/bash -c "usermod -aG ${additionalgroup} ${USERNAME} 2>/dev/null"
	done

	# fix for gksu in Xenial
	touch ${SDCARD}/home/${USERNAME}/.Xauthority
	chroot "${SDCARD}" /bin/bash -c "chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.Xauthority"
	# set up profile sync daemon on desktop systems
	chroot "${SDCARD}" /bin/bash -c "which psd >/dev/null 2>&1"
	if [ $? -eq 0 ]; then
		echo -e "${USERNAME} ALL=(ALL) NOPASSWD: /usr/bin/psd-overlay-helper" >> ${SDCARD}/etc/sudoers
		touch ${SDCARD}/home/${USERNAME}/.activate_psd
		chroot "${SDCARD}" /bin/bash -c "chown $USERNAME:$USERNAME /home/${USERNAME}/.activate_psd"
	fi

	# remove deb files
	rm -f "${SDCARD}"/root/*.deb

	[[ -f "${SDCARD}"/usr/bin/gnome-session ]] && sed -i "s/user-session.*/user-session=ubuntu-wayland/" ${SDCARD}/etc/lightdm/lightdm.conf.d/22-autologin.conf
	[[ -f "${SDCARD}"/usr/bin/startplasma-x11 ]] && sed -i "s/user-session.*/user-session=plasma-x11/" ${SDCARD}/etc/lightdm/lightdm.conf.d/22-autologin.conf

	# execute $LINUXFAMILY-specific tweaks
	[[ $(type -t family_tweaks) == function ]] && family_tweaks

	# enable additional services
	chroot "${SDCARD}" /bin/bash -c "systemctl --no-reload enable firstrun.service >/dev/null 2>&1"
	chroot "${SDCARD}" /bin/bash -c "systemctl --no-reload enable firstrun-config.service >/dev/null 2>&1"
	chroot "${SDCARD}" /bin/bash -c "systemctl --no-reload enable zram-config.service >/dev/null 2>&1"
	chroot "${SDCARD}" /bin/bash -c "systemctl --no-reload enable hardware-optimize.service >/dev/null 2>&1"
	chroot "${SDCARD}" /bin/bash -c "systemctl --no-reload enable ramlog.service >/dev/null 2>&1"
	chroot "${SDCARD}" /bin/bash -c "systemctl --no-reload enable resize-filesystem.service >/dev/null 2>&1"
	chroot "${SDCARD}" /bin/bash -c "systemctl --no-reload enable hardware-monitor.service >/dev/null 2>&1"

	# copy "first run automated config, optional user configured"
 	cp -v ${EXTER}/packages/bsp/first_run.txt.template "${SDCARD}"/boot/first_run.txt.template

	# Cosmetic fix [FAILED] Failed to start Set console font and keymap at first boot
	[[ -f "${SDCARD}"/etc/console-setup/cached_setup_font.sh ]] \
	&& sed -i "s/^printf '.*/printf '\\\033\%\%G'/g" "${SDCARD}"/etc/console-setup/cached_setup_font.sh
	[[ -f "${SDCARD}"/etc/console-setup/cached_setup_terminal.sh ]] \
	&& sed -i "s/^printf '.*/printf '\\\033\%\%G'/g" "${SDCARD}"/etc/console-setup/cached_setup_terminal.sh
	[[ -f "${SDCARD}"/etc/console-setup/cached_setup_keyboard.sh ]] \
	&& sed -i "s/-u/-x'/g" "${SDCARD}"/etc/console-setup/cached_setup_keyboard.sh

	# fix for https://bugs.launchpad.net/ubuntu/+source/blueman/+bug/1542723
	chroot "${SDCARD}" /bin/bash -c "chown root:messagebus /usr/lib/dbus-1.0/dbus-daemon-launch-helper"
	chroot "${SDCARD}" /bin/bash -c "chmod u+s /usr/lib/dbus-1.0/dbus-daemon-launch-helper"

	# disable samba NetBIOS over IP name service requests since it hangs when no network is present at boot
	chroot "${SDCARD}" /bin/bash -c "systemctl --quiet disable nmbd 2> /dev/null"

	# disable repeated messages due to xconsole not being installed.
	[[ -f "${SDCARD}"/etc/rsyslog.d/50-default.conf ]] && \
	sed '/daemon\.\*\;mail.*/,/xconsole/ s/.*/#&/' -i "${SDCARD}"/etc/rsyslog.d/50-default.conf

	# disable deprecated parameter
	sed '/.*$KLogPermitNonKernelFacility.*/,// s/.*/#&/' -i "${SDCARD}"/etc/rsyslog.conf

	# enable getty on multiple serial consoles
	# and adjust the speed if it is defined and different than 115200
	#
	# example: SERIALCON="ttyS0:15000000,ttyGS1"
	#
	ifs=$IFS
	for i in $(echo "${SERIALCON:-'ttyS0'}" | sed "s/,/ /g")
	do
		IFS=':' read -r -a array <<< "$i"
		[[ "${array[0]}" == "tty1" ]] && continue # Don't enable tty1 as serial console.
		display_alert "Enabling serial console" "${array[0]}" "info"
		# add serial console to secure tty list
		[ -z "$(grep -w '^${array[0]}' "${SDCARD}"/etc/securetty 2> /dev/null)" ] && \
		echo "${array[0]}" >>  "${SDCARD}"/etc/securetty
		if [[ ${array[1]} != "115200" && -n ${array[1]} ]]; then
			# make a copy, fix speed and enable
			cp -v "${SDCARD}"/lib/systemd/system/serial-getty@.service \
			"${SDCARD}/lib/systemd/system/serial-getty@${array[0]}.service"
			sed -i "s/--keep-baud 115200/--keep-baud ${array[1]},115200/" \
			"${SDCARD}/lib/systemd/system/serial-getty@${array[0]}.service"
		fi
		chroot "${SDCARD}" /bin/bash -c "systemctl daemon-reload"
		chroot "${SDCARD}" /bin/bash -c "systemctl --no-reload enable serial-getty@${array[0]}.service"
		if [[ "${array[0]}" == "ttyGS0" && $LINUXFAMILY == sun8i && $BRANCH == legacy ]]; then
			mkdir -p "${SDCARD}"/etc/systemd/system/serial-getty@ttyGS0.service.d
			cat <<-EOF > "${SDCARD}"/etc/systemd/system/serial-getty@ttyGS0.service.d/10-switch-role.conf
			[Service]
			ExecStartPre=-/bin/sh -c "echo 2 > /sys/bus/platform/devices/sunxi_usb_udc/otg_role"
			EOF
		fi
	done
	IFS=$ifs

	# to prevent creating swap file on NFS (needs specific kernel options)
	# and f2fs/btrfs (not recommended or needs specific kernel options)
	[[ $ROOTFS_TYPE != ext4 ]] && touch "${SDCARD}"/var/swap

	# install initial asound.state if defined
	mkdir -p "${SDCARD}"/var/lib/alsa/
	[[ -n $ASOUND_STATE ]] && cp -v "${EXTER}/packages/blobs/asound.state/${ASOUND_STATE}" "${SDCARD}"/var/lib/alsa/asound.state

	# save initial board-release state
	cp -v "${SDCARD}"/etc/board-release "${SDCARD}"/etc/image-release

	# DNS fix. package resolvconf is not available everywhere
	if [ -d /etc/resolvconf/resolv.conf.d ]; then
		echo "nameserver 8.8.8.8" > "${SDCARD}"/etc/resolvconf/resolv.conf.d/head
	fi

	# permit root login via SSH for the first boot
	sed -i 's/#\?PermitRootLogin .*/PermitRootLogin yes/' "${SDCARD}"/etc/ssh/sshd_config

	# enable PubkeyAuthentication
	sed -i 's/#\?PubkeyAuthentication .*/PubkeyAuthentication yes/' "${SDCARD}"/etc/ssh/sshd_config

	if [ -f "${SDCARD}"/etc/NetworkManager/NetworkManager.conf ]; then
		# configure network manager
		sed "s/managed=\(.*\)/managed=true/g" -i "${SDCARD}"/etc/NetworkManager/NetworkManager.conf

		# remove network manager defaults to handle eth by default
		rm -f "${SDCARD}"/usr/lib/NetworkManager/conf.d/10-globally-managed-devices.conf

		# most likely we don't need to wait for nm to get online
		chroot "${SDCARD}" /bin/bash -c "systemctl disable NetworkManager-wait-online.service"

		# Just regular DNS and maintain /etc/resolv.conf as a file
		sed "/dns/d" -i "${SDCARD}"/etc/NetworkManager/NetworkManager.conf
		sed "s/\[main\]/\[main\]\ndns=default\nrc-manager=file/g" -i "${SDCARD}"/etc/NetworkManager/NetworkManager.conf
		if [[ -n $NM_IGNORE_DEVICES ]]; then
			mkdir -p "${SDCARD}"/etc/NetworkManager/conf.d/
			cat <<-EOF > "${SDCARD}"/etc/NetworkManager/conf.d/10-ignore-interfaces.conf
			[keyfile]
			unmanaged-devices=$NM_IGNORE_DEVICES
			EOF
		fi
	elif [ -d "${SDCARD}"/etc/systemd/network ]; then
		# configure networkd
		rm "${SDCARD}"/etc/resolv.conf
		ln -s /run/systemd/resolve/resolv.conf "${SDCARD}"/etc/resolv.conf

		# enable services
		chroot "${SDCARD}" /bin/bash -c "systemctl enable systemd-networkd.service systemd-resolved.service"

		if  [ -e /etc/systemd/timesyncd.conf ]; then
			chroot "${SDCARD}" /bin/bash -c "systemctl enable systemd-timesyncd.service"
		fi
		umask 022
		cat > "${SDCARD}"/etc/systemd/network/eth0.network <<- __EOF__
		[Match]
		Name=eth0

		[Network]
		#MACAddress=
		DHCP=ipv4
		LinkLocalAddressing=ipv4
		#Address=192.168.1.100/24
		#Gateway=192.168.1.1
		#DNS=192.168.1.1
		#Domains=example.com
		NTP=0.pool.ntp.org 1.pool.ntp.org
		__EOF__

	fi

	# avahi daemon defaults if exists
	[[ -f "${SDCARD}"/usr/share/doc/avahi-daemon/examples/sftp-ssh.service ]] && \
	cp -v "${SDCARD}"/usr/share/doc/avahi-daemon/examples/sftp-ssh.service "${SDCARD}"/etc/avahi/services/
	[[ -f "${SDCARD}"/usr/share/doc/avahi-daemon/examples/ssh.service ]] && \
	cp -v "${SDCARD}"/usr/share/doc/avahi-daemon/examples/ssh.service "${SDCARD}"/etc/avahi/services/

	# nsswitch settings for sane DNS behavior: remove resolve, assure libnss-myhostname support
	sed "s/hosts\:.*/hosts:          files mymachines dns myhostname/g" -i "${SDCARD}"/etc/nsswitch.conf

	# disable MOTD for first boot - we want as clean 1st run as possible
	chmod -x "${SDCARD}"/etc/update-motd.d/*
}


# install_common
#
install_rclocal()
{
	cat <<-EOF > "${SDCARD}"/etc/rc.local
	#!/bin/sh -e
	#
	# rc.local
	#
	# This script is executed at the end of each multiuser runlevel.
	# Make sure that the script will "exit 0" on success or any other
	# value on error.
	#
	# In order to enable or disable this script just change the execution
	# bits.
	#
	# By default this script does nothing.

	exit 0
	EOF

	chmod +x "${SDCARD}"/etc/rc.local
}


# install_common
#
install_distribution_specific()
{
	display_alert "Applying distribution specific tweaks for" "$RELEASE" "info"

	case $RELEASE in

	buster)
			# remove doubled uname from motd
			[[ -f "${SDCARD}"/etc/update-motd.d/10-uname ]] && rm "${SDCARD}"/etc/update-motd.d/10-uname
			# rc.local is not existing but one might need it
			install_rclocal
		;;

	bullseye)
			# remove doubled uname from motd
			[[ -f "${SDCARD}"/etc/update-motd.d/10-uname ]] && rm "${SDCARD}"/etc/update-motd.d/10-uname
			# rc.local is not existing but one might need it
			install_rclocal
			# fix missing versioning
			[[ $(grep -L "VERSION_ID=" "${SDCARD}"/etc/os-release) ]] && echo 'VERSION_ID="11"' >> "${SDCARD}"/etc/os-release
			[[ $(grep -L "VERSION=" "${SDCARD}"/etc/os-release) ]] && echo 'VERSION="11 (bullseye)"' >> "${SDCARD}"/etc/os-release
		;;

	bookworm)
			# remove doubled uname from motd
			[[ -f "${SDCARD}"/etc/update-motd.d/10-uname ]] && rm "${SDCARD}"/etc/update-motd.d/10-uname
			# rc.local is not existing but one might need it
			install_rclocal
			# fix missing versioning
			[[ $(grep -L "VERSION_ID=" "${SDCARD}"/etc/os-release) ]] && echo 'VERSION_ID="12"' >> "${SDCARD}"/etc/os-release
			[[ $(grep -L "VERSION=" "${SDCARD}"/etc/os-release) ]] && echo 'VERSION="11 (bookworm)"' >> "${SDCARD}"/etc/os-release

			# remove security updates repository since it does not exists yet
			sed '/security/ d' -i "${SDCARD}"/etc/apt/sources.list
		;;

	bionic|focal|jammy)
			# by using default lz4 initrd compression leads to corruption, go back to proven method
			sed -i "s/^COMPRESS=.*/COMPRESS=gzip/" "${SDCARD}"/etc/initramfs-tools/initramfs.conf

			# cleanup motd services and related files
			chroot "${SDCARD}" /bin/bash -c "systemctl disable  motd-news.service >/dev/null 2>&1"
			chroot "${SDCARD}" /bin/bash -c "systemctl disable  motd-news.timer >/dev/null 2>&1"

			rm -f "${SDCARD}"/etc/update-motd.d/{10-uname,10-help-text,50-motd-news,80-esm,80-livepatch,90-updates-available,91-release-upgrade,95-hwe-eol}

			# remove motd news from motd.ubuntu.com
			[[ -f "${SDCARD}"/etc/default/motd-news ]] && sed -i "s/^ENABLED=.*/ENABLED=0/" "${SDCARD}"/etc/default/motd-news

			# rc.local is not existing but one might need it
			install_rclocal

			if [ -d "${SDCARD}"/etc/NetworkManager ]; then
				local RENDERER=NetworkManager
			else
				local RENDERER=networkd
			fi

			# Basic Netplan config. Let NetworkManager/networkd manage all devices on this system
			[[ -d "${SDCARD}"/etc/netplan ]] && cat <<-EOF > "${SDCARD}"/etc/netplan/default.yaml
			network:
			  version: 2
			  renderer: $RENDERER
			EOF

			# DNS fix
			sed -i "s/#DNS=.*/DNS=8.8.8.8/g" "${SDCARD}"/etc/systemd/resolved.conf

			# Journal service adjustements
			sed -i "s/#Storage=.*/Storage=volatile/g" "${SDCARD}"/etc/systemd/journald.conf
			sed -i "s/#Compress=.*/Compress=yes/g" "${SDCARD}"/etc/systemd/journald.conf
			sed -i "s/#RateLimitIntervalSec=.*/RateLimitIntervalSec=30s/g" "${SDCARD}"/etc/systemd/journald.conf
			sed -i "s/#RateLimitBurst=.*/RateLimitBurst=10000/g" "${SDCARD}"/etc/systemd/journald.conf

			# Chrony temporal fix https://bugs.launchpad.net/ubuntu/+source/chrony/+bug/1878005
			sed -i '/DAEMON_OPTS=/s/"-F -1"/"-F 0"/' "${SDCARD}"/etc/default/chrony

			# disable conflicting services
			chroot "${SDCARD}" /bin/bash -c "systemctl --no-reload mask ondemand.service >/dev/null 2>&1"
		;;
	esac

	# use list modules INITRAMFS
	if [ -f "${EXTER}"/config/modules/"${MODULES_INITRD}" ]; then
		display_alert "Use file list modules INITRAMFS" "${MODULES_INITRD}"
		sed -i "s/^MODULES=.*/MODULES=list/" "${SDCARD}"/etc/initramfs-tools/initramfs.conf
		cat "${EXTER}"/config/modules/"${MODULES_INITRD}" >> "${SDCARD}"/etc/initramfs-tools/modules
	fi
}


# post_debootstrap_tweaks
#
post_debootstrap_tweaks()
{
	# remove service start blockers and QEMU binary
	rm -f "${SDCARD}"/sbin/initctl "${SDCARD}"/sbin/start-stop-daemon
	chroot "${SDCARD}" /bin/bash -c "dpkg-divert --quiet --local --rename --remove /sbin/initctl"
	chroot "${SDCARD}" /bin/bash -c "dpkg-divert --quiet --local --rename --remove /sbin/start-stop-daemon"
	rm -f "${SDCARD}"/usr/sbin/policy-rc.d "${SDCARD}/usr/bin/${QEMU_BINARY}"
}
