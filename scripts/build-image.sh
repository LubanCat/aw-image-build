#!/bin/bash
#
# Copyright (c) 2013-2021 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.


# Functions:

# debootstrap_ng
# prepare_partitions
# update_initramfs
# create_image


# debootstrap_ng
#
debootstrap_ng()
{
	display_alert "Starting building image for" "${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED:-null} ${DESKTOP_ENVIRONMENT:-null}" "info"

	[[ $ROOTFS_TYPE != ext4 ]] && display_alert "Assuming $BOARD $BRANCH kernel supports $ROOTFS_TYPE" "" "wrn"

	# trap to unmount stuff in case of error/manual interruption
	trap unmount_on_exit INT TERM EXIT

	# stage: clean and create directories
	rm -rf $SDCARD $MOUNT
	mkdir -p $SDCARD $MOUNT $BUILD_DIR/images $EXTER/cache/rootfs

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

	local packages_hash=$(get_package_list_hash $ROOTFSCACHE_VERSION)
	local cache_type="server"
	[[ -n ${DESKTOP_ENVIRONMENT} ]] && local cache_type="${DESKTOP_ENVIRONMENT}"
	local cache_name=${RELEASE}-${cache_type}-${ARCH}.$packages_hash.tar.gz
	local cache_file=${BUILD_DIR}/rootfs-base/${cache_name}

	# 根据校验值判断根文件系统是否更改
	if [[ -f $cache_file ]]; then
		display_alert "Extracting base rootfs" "$cache_name $(( ($(date +%s) - $(stat -c %Y $cache_file)) / 86400 )) days old" "info"

		# 解压base-rootfs压缩包
		pv -p -b -r -c -N "[ .... ] $cache_name" "$cache_file" | pigz -d | sudo tar xp --xattrs -C $SDCARD/
		[[ $? -ne 0 ]]  && exit_with_error "Cache $cache_file is corrupted. Restart."
	else
		# base-rootfs不正确时报错退出
		display_alert "base rootfs has been changed" "$cache_name" "err"
		display_alert "please run command first" "./build.sh BUILD_OPT=rootfs" "err"
		exit
	fi

	# 挂载chroot所需目录
	mount_chroot "$SDCARD"

	# 根据系统版本调整根文件系统基本内容
	sudo bash -c "source $SCR_DIR/rootfs/distributions.sh install_distribution_specific"

	# 修改根文件系统与硬件相关的部分
	sudo bash -c "source $SCR_DIR/rootfs/distributions.sh install_common"

	umount_chroot "$SDCARD"

	# 清理空间
	sudo bash -c "source $SCR_DIR/rootfs/distributions.sh post_debootstrap_tweaks"

	# 创建镜像文件，分区并导入文件
	prepare_partitions

	# 向镜像中写入loader、根文件系统并打包发布
	create_image

	# stage: unmount tmpfs
	if [[ $use_tmpfs = yes ]]; then
		while grep -qs "$SDCARD" /proc/mounts
		do
			sudo umount $SDCARD
			sleep 5
		done
	fi
	# rm -rf $SDCARD

	# remove exit trap
	trap - INT TERM EXIT
}


# prepare_partitions
#
# creates image file, partitions and fs
# and mounts it to local dir
# FS-dependent stuff (boot and root fs partition types) happens here
#
prepare_partitions()
{
	display_alert "Preparing image file for rootfs" "$BOARD $RELEASE" "info"

	# possible partition combinations
	# /boot: none, ext4, ext2, fat (BOOTFS_TYPE)
	# root: ext4, btrfs, f2fs, nfs (ROOTFS_TYPE)

	# declare makes local variables by default if used inside a function
	# NOTE: mountopts string should always start with comma if not empty

	# array copying in old bash versions is tricky, so having filesystems as arrays
	# with attributes as keys is not a good idea
	declare -A parttype mkopts mkopts_label mkfs mountopts

	parttype[ext4]=ext4
	parttype[ext2]=ext2
	parttype[fat]=fat16
	parttype[f2fs]=ext4 # not a copy-paste error
	parttype[btrfs]=btrfs
	parttype[xfs]=xfs
	# parttype[nfs] is empty

	# metadata_csum and 64bit may need to be disabled explicitly when migrating to newer supported host OS releases
	if [[ $HOST_RELEASE =~ buster|bullseye|bookworm|bionic|focal|jammy|kinetic|sid ]]; then
		mkopts[ext4]="-q -m 2 -O ^64bit,^metadata_csum"
	fi
	# mkopts[fat] is empty
	mkopts[ext2]='-q'
	# mkopts[f2fs] is empty
	mkopts[btrfs]='-m dup'
	# mkopts[xfs] is empty
	# mkopts[nfs] is empty

	mkopts_label[ext4]='-L '
	mkopts_label[ext2]='-L '
	mkopts_label[fat]='-n '
	mkopts_label[f2fs]='-l '
	mkopts_label[btrfs]='-L '
	mkopts_label[xfs]='-L '
	# mkopts_label[nfs] is empty

	mkfs[ext4]=ext4
	mkfs[ext2]=ext2
	mkfs[fat]=vfat
	mkfs[f2fs]=f2fs
	mkfs[btrfs]=btrfs
	mkfs[xfs]=xfs
	# mkfs[nfs] is empty

	mountopts[ext4]=',commit=600,errors=remount-ro'
	# mountopts[ext2] is empty
	# mountopts[fat] is empty
	# mountopts[f2fs] is empty
	mountopts[btrfs]=',commit=600'
	# mountopts[xfs] is empty
	# mountopts[nfs] is empty

	ROOT_FS_LABEL="${ROOT_FS_LABEL:-rootfs}"
	BOOT_FS_LABEL="${BOOT_FS_LABEL:-boot}"

	# 默认分区序号
	local part_num=1

	# 检查是否需要boot分区
	if [[ -n $BOOTFS_TYPE || $ROOTFS_TYPE != ext4 ]]; then
		local bootpart=$((part_num++))
		local bootfs=${BOOTFS_TYPE:-ext4}
		[[ -z $BOOTSIZE || $BOOTSIZE -le 32 ]] && BOOTSIZE="32"
	else
		BOOTSIZE=0
	fi

	# 设置rootfs分区序号
	rootpart=$((part_num++))

	# 获取 rootfs 大小
	export rootfs_size=$(sudo du -sm $SDCARD/ | cut -f1) # MiB
	display_alert "Current rootfs size" "$rootfs_size MiB" "info"

	# 判断是否限制镜像大小
	if [[ -n $FIXED_IMAGE_SIZE && $FIXED_IMAGE_SIZE =~ ^[0-9]+$ ]]; then
		display_alert "Using user-defined image size" "$FIXED_IMAGE_SIZE MiB" "info"
		local sdsize=$FIXED_IMAGE_SIZE
		# basic sanity check
		if [[ $sdsize -lt $rootfs_size ]]; then
			exit_with_error "User defined image size is too small" "$sdsize <= $rootfs_size"
		fi
	else
		# 镜像大小 = loader预留空间 + boot分区大小 + rootfs分区大小 + rootfs扩展空间
		local imagesize=$(($LOADER_SIZE + $BOOTSIZE + $rootfs_size + $EXTRA_ROOTFS_MIB_SIZE)) # MiB
		# 预留一部分空间
		if [[ $BUILD_OS_TYPE == desktop ]]; then
			local sdsize=$(bc -l <<< "scale=0; ((($imagesize * 1.40) / 1 + 0) / 4 + 1) * 4")
		else
			local sdsize=$(bc -l <<< "scale=0; ((($imagesize * 1.30) / 1 + 0) / 4 + 1) * 4")
		fi
	fi

	display_alert "Creating blank image for rootfs" "$sdsize MiB" "info"
	# 创建一个空的镜像文件
	dd if=/dev/zero bs=1M status=none count=$sdsize | pv -p -b -r -s $(($sdsize * 1024 * 1024)) -N "[ .... ] dd" | dd status=none of=${SDCARD}.raw

	display_alert "Creating partitions" "${bootfs:+/boot: $bootfs }root: $ROOTFS_TYPE" "info"
	# 使用echo像sfdisk写入参数，创建分区
	{
	# 创建分区表
	[[ "$IMAGE_PARTITION_TABLE" == "msdos" ]] &&
		echo "label: dos" || echo "label: $IMAGE_PARTITION_TABLE"

	local start_value=$LOADER_SIZE

	# 如果存在boot分区，则创建
	if [[ -n "$bootpart" ]]; then
		# Linux extended boot
		[[ "$IMAGE_PARTITION_TABLE" != "gpt" ]] &&
			local type="ea" || local type="BC13C2FF-59E6-4262-A352-B275FD6F7172"

		if [[ -n "$rootpart" ]]; then
			echo "$bootpart : name=\"bootfs\", start=${start_value}MiB, size=${BOOTSIZE}MiB, type=${type}"
			local start_value=$(($start_value + $BOOTSIZE))
		else
			# no `size` argument mean "as much as possible"
			echo "$bootpart : name=\"bootfs\", start=${start_value}MiB, type=${type}"
		fi
	fi

	# 如果存在rootfs分区，则创建
	if [[ -n "$rootpart" ]]; then
		# dos: Linux
		# gpt: Linux filesystem
		[[ "$IMAGE_PARTITION_TABLE" != "gpt" ]] &&
			local type="83" ||	local type="0FC63DAF-8483-4772-8E79-3D69D8477DE4"
		# no `size` argument mean "as much as possible"
		echo "$rootpart : name=\"rootfs\", start=${start_value}MiB, type=${type}"
	fi
	} | sfdisk ${SDCARD}.raw || exit_with_error "Partition fail."


	# stage: mount image
	# lock access to loop devices
	exec {FD}> /var/lock/debootstrap-losetup
	flock -x $FD

	# 检查并挂载镜像到/dev/loop设备
	LOOP=$(sudo losetup -f)
	[[ -z $LOOP ]] && exit_with_error "Unable to find free loop device"

	check_loop_device "$LOOP"

	sudo losetup $LOOP ${SDCARD}.raw

	# loop device was grabbed here, unlock
	flock -u $FD

	sudo partprobe $LOOP

	# stage: create fs, mount partitions, create fstab
	sudo rm -f $SDCARD/etc/fstab
	# 格式化rootfs分区
	if [[ -n $rootpart ]]; then
		local rootdevice="${LOOP}p${rootpart}"
		check_loop_device "$rootdevice"
		display_alert "Creating rootfs" "$ROOTFS_TYPE on $rootdevice"

		# 使用mkfs命令格式化rootfs分区
		sudo mkfs.${mkfs[$ROOTFS_TYPE]} ${mkopts[$ROOTFS_TYPE]} ${mkopts_label[$ROOTFS_TYPE]:+${mkopts_label[$ROOTFS_TYPE]}"$ROOT_FS_LABEL"} $rootdevice

		[[ $ROOTFS_TYPE == ext4 ]] && sudo tune2fs -o journal_data_writeback $rootdevice > /dev/null

		if [[ $ROOTFS_TYPE == btrfs && $BTRFS_COMPRESSION != none ]]; then
			local fscreateopt="-o compress-force=${BTRFS_COMPRESSION}"
		fi

		sudo mount ${fscreateopt} $rootdevice $MOUNT/

		# 重建 fstab
		local rootfs="UUID=$(sudo blkid -s UUID -o value $rootdevice)"
		sudo bash -c "echo '$rootfs / ${mkfs[$ROOTFS_TYPE]} defaults,noatime${mountopts[$ROOTFS_TYPE]} 0 1 '>> $SDCARD/etc/fstab"
	else
		# update_initramfs will fail if /lib/modules/ doesn't exist
		sudo mount --bind --make-private $SDCARD $MOUNT/
		sudo bash -c "echo '/dev/nfs / nfs defaults 0 0' >> $SDCARD/etc/fstab"
	fi

	# 格式化boot分区
	if [[ -n $bootpart ]]; then
		display_alert "Creating /boot" "$bootfs on ${LOOP}p${bootpart}"
		check_loop_device "${LOOP}p${bootpart}"
		sudo mkfs.${mkfs[$bootfs]} ${mkopts[$bootfs]} ${mkopts_label[$bootfs]:+${mkopts_label[$bootfs]}"$BOOT_FS_LABEL"} ${LOOP}p${bootpart}
		sudo mkdir -p $MOUNT/boot/
		sudo mount ${LOOP}p${bootpart} $MOUNT/boot/
		sudo bash -c "echo 'UUID=$(sudo blkid -s UUID -o value ${LOOP}p${bootpart}) /boot ${mkfs[$bootfs]} defaults${mountopts[$bootfs]} 0 2' >> $SDCARD/etc/fstab"
	fi

	sudo bash -c "echo 'tmpfs /tmp tmpfs defaults,nosuid 0 0' >> $SDCARD/etc/fstab"

	# 创建autoEnv变量
	sudo bash -c "echo 'rootdev=$rootfs' >> $SDCARD/boot/autoEnv"
	sudo bash -c "echo 'rootfstype=$ROOTFS_TYPE' >> $SDCARD/boot/autoEnv"
	
	# 修复boot.cmd启动脚本
	if [[ $rootpart != 1 ]] ; then
		sudo sed -i 's/mmcblk0p1/mmcblk0p2/' $SDCARD/boot/boot.cmd
		sudo sed -i 's/mmcblk1p1/mmcblk1p2/' $SDCARD/boot/boot.cmd
		sudo sed -i -e "s/rootfstype=ext4/rootfstype=$ROOTFS_TYPE/" \
			-e "s/rootfstype \"ext4\"/rootfstype \"$ROOTFS_TYPE\"/" $SDCARD/boot/boot.cmd
	fi

	# recompile .cmd to .scr if boot.cmd exists
	if [[ -f $SDCARD/boot/boot.cmd ]]; then
		mkimage -C none -A arm -T script -d $SDCARD/boot/boot.cmd $SDCARD/boot/boot.scr > /dev/null 2>&1
	fi

}


# update_initramfs
#
# this should be invoked as late as possible for any modifications by
#  prepare_partitions to be reflected in the final initramfs
#
# especially, this needs to be invoked after /etc/crypttab has been created
# for cryptroot-unlock to work:
# https://serverfault.com/questions/907254/cryproot-unlock-with-dropbear-timeout-while-waiting-for-askpass
#
# since Debian buster, it has to be called within create_image() on the $MOUNT
# path instead of $SDCARD (which can be a tmpfs and breaks cryptsetup-initramfs).
#
update_initramfs()
{
	local chroot_target=$1
	local target_dir=$(
		find ${chroot_target}/lib/modules/ -maxdepth 1 -type d -name "*${LINUX}*"
	)
	if [ "$target_dir" != "" ]; then
		update_initramfs_cmd="update-initramfs -uv -k $(basename $target_dir)"
	else
		exit_with_error "No kernel installed for the version" "${LINUX}"
	fi
	display_alert "Updating initramfs..." "$update_initramfs_cmd" ""
	sudo cp /usr/bin/$QEMU_BINARY $chroot_target/usr/bin/
	mount_chroot "$chroot_target/"

	sudo bash -c "chroot $chroot_target /bin/bash -c '$update_initramfs_cmd' >> ${LOG_PATH}/install.log 2>&1" || {
		display_alert "Updating initramfs FAILED, see:" "${LOG_PATH}/install.log" "err"
		exit 23
	}
	display_alert "Updated initramfs." "for details see: ${LOG_PATH}/install.log" "info"

	display_alert "Re-enabling" "initramfs-tools hook for kernel"
	sudo bash -c "chroot $chroot_target /bin/bash -c 'chmod -v +x /etc/kernel/postinst.d/initramfs-tools'"

	umount_chroot "$chroot_target/"
	sudo rm $chroot_target/usr/bin/$QEMU_BINARY
}


# create_image
#
# finishes creation of image from cached rootfs
#
create_image()
{
	local version="${BOARD}-${DISTRIBUTION}-${RELEASE}-${BUILD_OS_TYPE}${DESKTOP_ENVIRONMENT:+-$DESKTOP_ENVIRONMENT}-linux-$LINUX-$(date +%G%m%d)"
	version="${version,,}"

	IMG_OUT_DIR=$OUT_DIR/images/${version}
	rm -rf $IMG_OUT_DIR
	mkdir -p $IMG_OUT_DIR

	display_alert "Copying files to" "/"
	sudo rsync -aHWXh \
			--exclude="/boot/*" \
			--exclude="/dev/*" \
			--exclude="/proc/*" \
			--exclude="/run/*" \
			--exclude="/tmp/*" \
			--exclude="/sys/*" \
			--info=progress0,stats1 $SDCARD/ $MOUNT/


	# stage: rsync /boot
	display_alert "Copying files to" "/boot" "info"
	if [[ $(findmnt --target $MOUNT/boot -o FSTYPE -n) == vfat ]]; then
		# fat32
		sudo rsync -rLtWh \
			  --info=progress0,stats1 \
			  --log-file=${LOG_PATH}/install.log $SDCARD/boot $MOUNT
	else
		# ext4
		sudo rsync -aHWXh \
			  --info=progress0,stats1 \
			  --log-file=${LOG_PATH}/install.log $SDCARD/boot $MOUNT
	fi

	# stage: create final initramfs
	[[ -n $LINUX_SOURCE ]] && {
		update_initramfs $MOUNT
	}

	# DEBUG: print free space
	df -h

	# stage: write u-boot
	sudo bash -c "source $SCR_DIR/write-uboot.sh $LOOP"

	# fix wrong / permissions
	sudo chmod 755 $MOUNT

	# unmount /boot, rootfs  image file last
	sync

	[[ -n $BOOTFS_TYPE ]] && sudo umount -l $MOUNT/boot

	sudo umount -l $MOUNT

	# to make sure its unmounted
	while grep -Eq '(${MOUNT}|${IMG_BUILD_DIR})' /proc/mounts
	do
		display_alert "Wait for unmount" "${MOUNT}" "info"
		sleep 5
	done

	sudo losetup -d $LOOP

	sudo rm -rf --one-file-system  "$IMG_BUILD_DIR" "$MOUNT"

	mkdir -p $IMG_BUILD_DIR

	mv ${SDCARD}.raw $IMG_BUILD_DIR/${version}.img

	[[ -z $IMAGE_OUT_FILES ]] && IMAGE_OUT_FILES="md5,img,gz"

	cd ${IMG_BUILD_DIR}

	if [[ $IMAGE_OUT_FILES == *gz* ]]; then
		display_alert "Compressing" "${IMG_BUILD_DIR}/${version}.img.gz" "info"
		pigz -k ${version}.img
	fi

	if [[ $IMAGE_OUT_FILES == *xz* ]]; then
		display_alert "Compressing" "${IMG_BUILD_DIR}/${version}.img.xz" "info"
		pixz -k ${version}.img
	fi

	if [[ $IMAGE_OUT_FILES == *7z* ]]; then
		display_alert "Compressing" "${IMG_BUILD_DIR}/${version}.7z" "info"
		7za a ${version}.7z ${version}.img
	fi

	if [[ $IMAGE_OUT_FILES == *md5* ]]; then
		display_alert "MD5 calculating" "${version}.md5" "info"
		md5sum -b ./* > ${version}.md5
	fi

	mv $IMG_BUILD_DIR/${version}* ${IMG_OUT_DIR}

	display_alert "Done building" "${IMG_OUT_DIR}/${version}.img" "info"
}
