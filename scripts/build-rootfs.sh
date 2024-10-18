#!/bin/bash
#
# Functions:
# create_base_rootfs
# create_server_bsp_package
# create_distro_package
# create_desktop_bsp_package
# add_apt_sources



# create_base_rootfs
#
# unpacks cached rootfs for $RELEASE or creates one
#
create_base_rootfs()
{
	local packages_hash=$(get_package_list_hash $ROOTFSCACHE_VERSION)

	local cache_type="server"
	[[ -n ${DESKTOP_ENVIRONMENT} ]] && local cache_type="${DESKTOP_ENVIRONMENT}"

	local cache_name=${RELEASE}-${cache_type}-${ARCH}.$packages_hash.tar.gz
	local cache_file=${BUILD_DIR}/rootfs-base/${cache_name}
	mkdir -p ${BUILD_DIR}/rootfs-base

	sudo rm -rf "$SDCARD"
	mkdir -p "$SDCARD"

	# stage: verify tmpfs configuration and mount
	# CLI needs ~1.5GiB, desktop - ~3.5GiB
	# calculate and set tmpfs mount to use 9/10 of available RAM+SWAP
	local phymem=$(( (($(awk '/MemTotal/ {print $2}' /proc/meminfo) + $(awk '/SwapTotal/ {print $2}' /proc/meminfo))) / 1024 * 9 / 10 )) # MiB
	if [[ $BUILD_OS_TYPE == desktop ]]; then
		local tmpfs_max_size=4096;
	else
		local tmpfs_max_size=2048;
	fi # MiB

	if [[ $phymem -gt $tmpfs_max_size ]]; then
		local use_tmpfs=yes
	fi

	# 判断 当系统可用内存足够时挂载tmpfs，增加读写性能
	[[ $use_tmpfs == yes ]] && sudo mount -t tmpfs -o size=${phymem}M tmpfs $SDCARD

	# 根据校验值判断根文件系统是否更改，未更改使用同名压缩包
	if [[ -f $cache_file ]]; then

		display_alert "base-rootfs not change, skip" "$cache_name $(( ($(date +%s) - $(stat -c %Y $cache_file)) / 86400 )) days old" "info"
		display_alert "if you want to rebuild, delate" "${BUILD_DIR}/rootfs-base/$cache_name" "info"

	else
		display_alert "local not found" "Creating new $RELEASE base-rootfs" "info"

		sudo bash -c "source $SCR_DIR/rootfs/debootstrap.sh"

	fi

	[[ $use_tmpfs == yes ]] && sudo umount --lazy "$SDCARD"

	display_alert "Rootfs base build done" "$HOSTNAME@host" "info"
	display_alert "Target directory" "${BUILD_DIR}/rootfs-base" "info"
	display_alert "File name" "${cache_name}" "info"
}


# create_server_bsp_package
#
# build board bsp deb packages
#
create_server_bsp_package()
{
	display_alert "Creating server bsp" "$BSP_SERVER_DEB_NAME" "info"

	bsptempdir=$(mktemp -d)
	chmod 700 ${bsptempdir}
	trap "rm -rf \"${bsptempdir}\" ; exit 0" 0 1 2 3 15
	local destination=${bsptempdir}/${RELEASE}/${BSP_SERVER_DEB_FULLNAME}
	mkdir -p "${destination}"/DEBIAN
	cd $destination

	# copy general overlay from packages/bsp-cli
	copy_all_packages_files_for "bsp-cli"

	# Replaces: base-files is needed to replace /etc/update-motd.d/ files on Xenial
	# Replaces: unattended-upgrades may be needed to replace /etc/apt/apt.conf.d/50unattended-upgrades
	# (distributions provide good defaults, so this is not needed currently)
	# Depends: linux-base is needed for "linux-version" command in initrd cleanup script
	# Depends: fping is needed for systemmonitor to upload hardware-monitor.log
	cat <<-EOF > "${destination}"/DEBIAN/control
	Package: ${BSP_SERVER_DEB_NAME}
	Version: $REVISION
	Architecture: $ARCH
	Maintainer: Embedfire <embedfire@embedfire.com>
	Depends: bash, linux-base, u-boot-tools, initramfs-tools, lsb-release, fping
	Replaces: zram-config, base-files, lbc-tools
	Recommends: bsdutils, parted, util-linux, toilet
	Description: LubanCat board support files for $BOARD
	EOF

	# set up pre install script
	cat <<-EOF > "${destination}"/DEBIAN/preinst
	#!/bin/sh

	# tell people to reboot at next login
	[ "\$1" = "upgrade" ] && touch /var/run/.reboot_required

	# convert link to file
	if [ -L "/etc/network/interfaces" ]; then

	    cp /etc/network/interfaces /etc/network/interfaces.tmp
	    rm /etc/network/interfaces
	    mv /etc/network/interfaces.tmp /etc/network/interfaces

	fi

	# fixing ramdisk corruption when using lz4 compression method
	sed -i "s/^COMPRESS=.*/COMPRESS=gzip/" /etc/initramfs-tools/initramfs.conf

	# swap
	grep -q vm.swappiness /etc/sysctl.conf
	case \$? in
	0)
	    sed -i 's/vm\.swappiness.*/vm.swappiness=100/' /etc/sysctl.conf
	    ;;
	*)
	    echo vm.swappiness=100 >>/etc/sysctl.conf
	    ;;
	esac
	sysctl -p >/dev/null 2>&1

	# disable deprecated services
	[ -f "/etc/profile.d/activate_psd_user.sh" ] && rm /etc/profile.d/activate_psd_user.sh
	[ -f "/etc/profile.d/check_first_login.sh" ] && rm /etc/profile.d/check_first_login.sh
	[ -f "/etc/profile.d/check_first_login_reboot.sh" ] && rm /etc/profile.d/check_first_login_reboot.sh
	[ -f "/etc/profile.d/ssh-title.sh" ] && rm /etc/profile.d/ssh-title.sh
	[ -f "/etc/update-motd.d/10-header" ] && rm /etc/update-motd.d/10-header
	[ -f "/etc/update-motd.d/30-sysinfo" ] && rm /etc/update-motd.d/30-sysinfo
	[ -f "/etc/update-motd.d/35-tips" ] && rm /etc/update-motd.d/35-tips
	[ -f "/etc/update-motd.d/40-updates" ] && rm /etc/update-motd.d/40-updates
	[ -f "/etc/update-motd.d/98-autoreboot-warn" ] && rm /etc/update-motd.d/98-autoreboot-warn
	[ -f "/etc/update-motd.d/99-point-to-faq" ] && rm /etc/update-motd.d/99-point-to-faq
	[ -f "/etc/update-motd.d/80-esm" ] && rm /etc/update-motd.d/80-esm
	[ -f "/etc/update-motd.d/80-livepatch" ] && rm /etc/update-motd.d/80-livepatch
	[ -f "/etc/apt/apt.conf.d/02compress-indexes" ] && rm /etc/apt/apt.conf.d/02compress-indexes
	[ -f "/etc/apt/apt.conf.d/02periodic" ] && rm /etc/apt/apt.conf.d/02periodic
	[ -f "/etc/apt/apt.conf.d/no-languages" ] && rm /etc/apt/apt.conf.d/no-languages
	[ -f "/etc/init.d/armhwinfo" ] && rm /etc/init.d/armhwinfo
	[ -f "/etc/logrotate.d/armhwinfo" ] && rm /etc/logrotate.d/armhwinfo
	[ -f "/etc/init.d/firstrun" ] && rm /etc/init.d/firstrun
	[ -f "/etc/init.d/resize2fs" ] && rm /etc/init.d/resize2fs
	[ -f "/lib/systemd/system/firstrun-config.service" ] && rm /lib/systemd/system/firstrun-config.service
	[ -f "/lib/systemd/system/firstrun.service" ] && rm /lib/systemd/system/firstrun.service
	[ -f "/lib/systemd/system/resize2fs.service" ] && rm /lib/systemd/system/resize2fs.service
	[ -f "/usr/lib/lbc/apt-updates" ] && rm /usr/lib/lbc/apt-updates
	[ -f "/usr/lib/lbc/firstrun-config.sh" ] && rm /usr/lib/lbc/firstrun-config.sh
	# fix for https://bugs.launchpad.net/ubuntu/+source/lightdm-gtk-greeter/+bug/1897491
	[ -d "/var/lib/lightdm" ] && (chown -R lightdm:lightdm /var/lib/lightdm ; chmod 0750 /var/lib/lightdm)
	exit 0
	EOF

	chmod 755 "${destination}"/DEBIAN/preinst

	# postrm script
	cat <<-EOF > "${destination}"/DEBIAN/postrm
	#!/bin/sh
	if [ remove = "\$1" ] || [ abort-install = "\$1" ]; then

	    systemctl disable hardware-monitor.service hardware-optimize.service >/dev/null 2>&1
	    systemctl disable zram-config.service ramlog.service >/dev/null 2>&1

	fi
	exit 0
	EOF

	chmod 755 "${destination}"/DEBIAN/postrm

	# set up post install script
	cat <<-EOF > "${destination}"/DEBIAN/postinst
	#!/bin/sh
	#
	# ${BOARD} BSP post installation script
	#

	[ -f /etc/lib/systemd/system/ramlog.service ] && systemctl --no-reload enable ramlog.service

	# check if it was disabled in config and disable in new service
	if [ -n "\$(grep -w '^ENABLED=false' /etc/default/log2ram 2> /dev/null)" ]; then

	     sed -i "s/^ENABLED=.*/ENABLED=false/" /etc/default/ramlog

	fi

	# fix boot delay "waiting for suspend/resume device"
	if [ -f "/etc/initramfs-tools/initramfs.conf" ]; then

	    if ! grep --quiet "RESUME=none" /etc/initramfs-tools/initramfs.conf; then
	         echo "RESUME=none" >> /etc/initramfs-tools/initramfs.conf
	    fi

	fi

	EOF
	# install bootscripts if they are not present. Fix upgrades from old images

	cat <<-EOF >> "${destination}"/DEBIAN/postinst
	[ ! -f "/etc/network/interfaces" ] && [ -f "/etc/network/interfaces.default" ] && cp /etc/network/interfaces.default /etc/network/interfaces
	ln -sf /var/run/motd /etc/motd

	if [ ! -f "/etc/default/ramlog" ] && [ -f /etc/default/ramlog.dpkg-dist ]; then
		mv /etc/default/ramlog.dpkg-dist /etc/default/ramlog
	fi
	if [ ! -f "/etc/default/zram-config" ] && [ -f /etc/default/zram-config.dpkg-dist ]; then
		mv /etc/default/zram-config.dpkg-dist /etc/default/zram-config
	fi

	if [ -L "/usr/lib/chromium-browser/master_preferences.dpkg-dist" ]; then
		mv /usr/lib/chromium-browser/master_preferences.dpkg-dist /usr/lib/chromium-browser/master_preferences
	fi

	# Reload services
	systemctl --no-reload enable hardware-monitor.service hardware-optimize.service zram-config.service >/dev/null 2>&1
	exit 0
	EOF

	chmod 755 "${destination}"/DEBIAN/postinst

	# copy common files from a premade directory structure
	rsync -a "${EXTER}"/packages/bsp/common/* ${destination}

	# trigger uInitrd creation after installation, to apply
	# /etc/initramfs/post-update.d/99-uboot
	cat <<-EOF > "${destination}"/DEBIAN/triggers
	activate update-initramfs
	EOF

	# armhwinfo, firstrun, systemmonitor, etc. config file
	cat <<-EOF > "${destination}"/etc/board-release
	# PLEASE DO NOT EDIT THIS FILE
	BOARD=${BOARD}
	BOARD_NAME="$BOARD_NAME"
	LINUXFAMILY=${LINUXFAMILY}
	DISTRIBUTION_CODENAME=${RELEASE}
	DISTRIBUTION_STATUS=${DISTRIBUTION_STATUS}
	VERSION=${REVISION}
	LINUXFAMILY=${LINUXFAMILY}
	ARCH=${ARCH}
	INITRD_ARCH=${INITRD_ARCH}
	KERNEL_IMAGE_TYPE=${KERNEL_IMAGE_TYPE}
	BRANCH=${BRANCH}
	LOADER_SIZE=${LOADER_SIZE}
	EOF

	# this is required for NFS boot to prevent deconfiguring the network on shutdown
	sed -i 's/#no-auto-down/no-auto-down/g' "${destination}"/etc/network/interfaces.default

	# execute $LINUXFAMILY-specific tweaks
	[[ $(type -t family_tweaks_bsp) == function ]] && family_tweaks_bsp

	# add some summary to the image
	fingerprint_image "${destination}/etc/buidlinfo"

	# fixing permissions (basic), reference: dh_fixperms
	find "${destination}" -print0 2>/dev/null | xargs -0r sudo chown --no-dereference 0:0
	find "${destination}" ! -type l -print0 2>/dev/null | xargs -0r sudo chmod 'go=rX,u+rw,a-s'

	# create board DEB file
	fakeroot dpkg-deb -b -Zxz "${destination}" "${destination}.deb" 
	mkdir -p "${DEB_DIR}/${RELEASE}/"
	rsync --remove-source-files -rq "${destination}.deb" "${DEB_DIR}/${RELEASE}/"

	# cleanup
	sudo rm -rf ${bsptempdir}
}


# create_distro_package
#
create_distro_package ()
{
	local destination tmp_dir
	tmp_dir=$(mktemp -d)
	destination=${tmp_dir}/${BOARD}/${CHOSEN_DESKTOP}_${REVISION}_all
	rm -rf "${destination}"
	mkdir -p "${destination}"/DEBIAN

	# set up control file
	cat <<-EOF > "${destination}"/DEBIAN/control
	Package: ${CHOSEN_DESKTOP}
	Version: $REVISION
	Architecture: all
	Maintainer: Embedfire <embedfire@embedfire.com>
	Description: LubanCat desktop for ${DISTRIBUTION} ${RELEASE}
	EOF

	# Recreating the DEBIAN/postinst file
	echo "#!/bin/sh -e" > "${destination}/DEBIAN/postinst"

	local aggregated_content=""
	aggregate_all_desktop "debian/postinst" $'\n'
	echo "${aggregated_content}" >> "${destination}/DEBIAN/postinst"
	echo "exit 0" >> "${destination}/DEBIAN/postinst"
	chmod 755 "${destination}"/DEBIAN/postinst
	#display_alert "Showing ${destination}/DEBIAN/postinst"
	cat "${destination}/DEBIAN/postinst"
	# LubanCat create_desktop_package scripts
	unset aggregated_content

	mkdir -p "${destination}"/etc/lbc

	local aggregated_content=""
	aggregate_all_desktop "create_desktop_package.sh" $'\n'
	eval "${aggregated_content}"
	[[ $? -ne 0 ]] && display_alert "create_desktop_package.sh exec error" "" "wrn"

	display_alert "Building package" "${CHOSEN_DESKTOP}_${REVISION}_all" "info"

	mkdir -p "${DEB_DIR}/${RELEASE}"
	cd "${destination}"; cd ..
	echo fakeroot dpkg-deb -b -Zxz "${destination}" "${DEB_DIR}/${RELEASE}/${CHOSEN_DESKTOP}_${REVISION}_all.deb"
	fakeroot dpkg-deb -b -Zxz "${destination}" "${DEB_DIR}/${RELEASE}/${CHOSEN_DESKTOP}_${REVISION}_all.deb"  >/dev/null

	# cleanup
	rm -rf "${tmp_dir}"

	unset aggregated_content
}


# create_desktop_bsp_package
#
create_desktop_bsp_package ()
{
	copy_all_packages_files_for "bsp-desktop"
}


# add_apt_sources
#
add_apt_sources() {
	local potential_paths=""
	local sub_dirs_to_check=". "
	if [[ ! -z "${BUILD_OS_TYPE+x}" ]]; then
		sub_dirs_to_check+="config_${BUILD_OS_TYPE}"
	fi
	get_all_potential_paths "${DEBOOTSTRAP_SEARCH_RELATIVE_DIRS}" "${sub_dirs_to_check}" "sources/apt"
	get_all_potential_paths "${CLI_SEARCH_RELATIVE_DIRS}" "${sub_dirs_to_check}" "sources/apt"
	get_all_potential_paths "${DESKTOP_ENVIRONMENTS_SEARCH_RELATIVE_DIRS}" "." "sources/apt"
	get_all_potential_paths "${DESKTOP_APPGROUPS_SEARCH_RELATIVE_DIRS}" "${DESKTOP_APPGROUPS_SELECTED}" "sources/apt"

	display_alert "Adding additional apt sources"

	for apt_sources_dirpath in ${potential_paths}; do
		if [[ -d "${apt_sources_dirpath}" ]]; then
			for apt_source_filepath in "${apt_sources_dirpath}/"*.source; do
				apt_source_filepath=$(echo $apt_source_filepath | sed -re 's/(^.*[^/])\.[^./]*$/\1/')
				local new_apt_source="$(cat "${apt_source_filepath}.source")"
				local apt_source_gpg_filepath="${apt_source_filepath}.gpg"

				# extract filenames
				local apt_source_gpg_filename="$(basename ${apt_source_gpg_filepath})"
				local apt_source_filename="$(basename ${apt_source_filepath}).list"

				display_alert "Adding APT Source ${new_apt_source}"

				if [[ "${new_apt_source}" == ppa* ]] ; then
					# ppa with software-common-properties
					chroot "${SDCARD}" /bin/bash -c "add-apt-repository -y -n \"${new_apt_source}\""
					# add list with apt-add
					# -y -> Assumes yes to all queries
					# -n -> Do not update package cache after adding
					if [[ -f "${apt_source_gpg_filepath}" ]]; then
						 display_alert "Adding GPG Key ${apt_source_gpg_filepath}"
						cp "${apt_source_gpg_filepath}" "${SDCARD}/tmp/${apt_source_gpg_filename}"
						chroot "${SDCARD}" /bin/bash -c "apt-key add \"/tmp/${apt_source_gpg_filename}\""
						echo "APT Key returned : $?"
					fi
				else
					# installation without software-common-properties, sources.list + key.gpg
					echo "${new_apt_source}" > "${SDCARD}/etc/apt/sources.list.d/${apt_source_filename}"
					if [[ -f "${apt_source_gpg_filepath}" ]]; then
						display_alert "Adding GPG Key ${apt_source_gpg_filepath}"
#						local apt_source_gpg_filename="$(basename ${apt_source_gpg_filepath})"
						mkdir -p "${SDCARD}"/usr/share/keyrings/
						cp "${apt_source_gpg_filepath}" "${SDCARD}"/usr/share/keyrings/
					fi
				fi
			done
		fi
	done
}
