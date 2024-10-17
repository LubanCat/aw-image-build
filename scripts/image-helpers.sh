#!/bin/bash
#
# Copyright (c) 2013-2021 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.


# Functions:

# mount_chroot
# umount_chroot
# unmount_on_exit
# check_loop_device
# write_uboot
# copy_all_packages_files_for
# install_deb_chroot


# mount_chroot <target>
#
# helper to reduce code duplication
#
mount_chroot()
{
	local target=$1
	sudo mount -t proc chproc "${target}"/proc
	sudo mount -t sysfs chsys "${target}"/sys
	sudo mount -t devtmpfs chdev "${target}"/dev || sudo mount --bind /dev "${target}"/dev
	sudo mount -t devpts chpts "${target}"/dev/pts
}


# umount_chroot <target>
#
# helper to reduce code duplication
#
umount_chroot()
{
	local target=$1
	display_alert "Unmounting" "$target" "info"
	while grep -Eq "${target}.*(dev|proc|sys)" /proc/mounts
	do
		sudo umount -l --recursive "${target}"/dev >/dev/null 2>&1
		sudo umount -l "${target}"/proc >/dev/null 2>&1
		sudo umount -l "${target}"/sys >/dev/null 2>&1
		sleep 5
	done
}


# unmount_on_exit
#
unmount_on_exit()
{
	trap - INT TERM EXIT
	local stacktrace="$(get_extension_hook_stracktrace "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}")"
	display_alert "unmount_on_exit() called!" "$stacktrace" "err"
	if [[ "${ERROR_DEBUG_SHELL}" == "yes" ]]; then
		ERROR_DEBUG_SHELL=no # dont do it twice
		display_alert "MOUNT" "${MOUNT}" "err"
		display_alert "SDCARD" "${SDCARD}" "err"
		display_alert "ERROR_DEBUG_SHELL=yes, starting a shell." "ERROR_DEBUG_SHELL" "err"
		bash < /dev/tty || true
	fi

	umount_chroot "${SDCARD}/"
	sudo umount -l "${SDCARD}"/tmp >/dev/null 2>&1
	sudo umount -l "${SDCARD}" >/dev/null 2>&1
	sudo umount -l "${MOUNT}"/boot >/dev/null 2>&1
	sudo umount -l "${MOUNT}" >/dev/null 2>&1
	sudo losetup -d "${LOOP}" >/dev/null 2>&1
	sudo rm -rf --one-file-system "${SDCARD}"
	exit_with_error "debootstrap-ng was interrupted" || true # don't trigger again
}


# check_loop_device <device_node>
#
check_loop_device()
{
	local device=$1
	if [[ ! -b $device ]]; then
		if [[ $CONTAINER_COMPAT == yes && -b /tmp/$device ]]; then
			display_alert "Creating device node" "$device"
			mknod -m0660 "${device}" b "0x$(stat -c '%t' "/tmp/$device")" "0x$(stat -c '%T' "/tmp/$device")"
		else
			exit_with_error "Device node $device does not exist"
		fi
	fi
}


# write_uboot <loopdev>
#
write_uboot()
{
	local loop=$1
	display_alert "Writing U-boot bootloader" "$loop" "info"
	TEMP_DIR=$(mktemp -d || exit 1)
	chmod 700 ${TEMP_DIR}

	dpkg -x "${DEB_DIR}/u-boot/${UBOOT_DEB}_${REVISION}_${ARCH}.deb" ${TEMP_DIR}/

	# source platform install to read $DIR
	source ${TEMP_DIR}/usr/lib/u-boot/platform_install.sh
	write_uboot_platform "${TEMP_DIR}${DIR}" "$loop"
	[[ $? -ne 0 ]] && exit_with_error "U-boot bootloader failed to install" "@host"
	rm -rf ${TEMP_DIR}
}


# copy_all_packages_files_for <folder> to package
#
copy_all_packages_files_for()
{
	local package_name="${1}"
	for package_src_dir in ${PACKAGES_SEARCH_ROOT_ABSOLUTE_DIRS};
	do
		local package_dirpath="${package_src_dir}/${package_name}"
		if [ -d "${package_dirpath}" ];
		then
			cp -vr "${package_dirpath}/"* "${destination}/"
			display_alert "Adding files from" "${package_dirpath}"
		fi
	done
}


# deb安装函数
# package: 要安装的软件包名称
# variant: remote在线安装，否则安装本地软件包
install_deb_chroot()
{
	local package=$1
	local variant=$2
	local name
	local desc
	if [[ ${variant} != remote ]]; then
		name="/root/"$(basename "${package}")
		[[ ! -f "${SDCARD}${name}" ]] && cp "${package}" "${SDCARD}${name}"
		desc=" from locale"
	else
		name=$1
		desc=" from online"
	fi

	display_alert "Installing deb${desc}" "${name/\/root\//}"
	chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -yqq --no-install-recommends install $name"
	[[ $? -ne 0 ]] && exit_with_error "Installation deb $name failed" "${BOARD} ${RELEASE} ${BUILD_OS_TYPE} ${LINUXFAMILY}"
}

