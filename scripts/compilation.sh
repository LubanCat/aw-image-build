#!/bin/bash
#
# Copyright (c) 2013-2021 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.


# Functions:
# compile_atf
# compile_uboot
# compile_kernel
# compile_firmware
# compile_sunxi_tools


# debootstrap_ng
#
compile_atf()
{
	display_alert "Compiler ATF path" "$ATF_DIR" "info"
	cd ${ATF_DIR} || exit

	display_alert "Compiler ATF clean" "make distclean" "info"
	make distclean

	display_alert "Compiler ATF command" "make $CTHREADS ENABLE_BACKTRACE=0 $ATF_MAKE_ARGS CROSS_COMPILE=$CCACHE $ATF_COMPILER" "info"
	eval CCACHE_BASEDIR="$(pwd)" 'make ENABLE_BACKTRACE="0" $ATF_MAKE_ARGS $CTHREADS CROSS_COMPILE="$CCACHE $ATF_COMPILER"'

	[[ $(type -t atf_custom_postprocess) == function ]] && atf_custom_postprocess
}


# compile_uboot
#
compile_uboot()
{
	cd "${UBOOT_DIR}" || exit
	display_alert "Compiler uboot info" "Uboot $UBOOT" "info"
	display_alert "Compiler uboot path" "$UBOOT_DIR" "info"

	# 创建deb包目录
	uboottempdir=$(mktemp -d)
	chmod 700 ${uboottempdir}
	trap "ret=\$?; rm -rf \"${uboottempdir}\" ; exit \$ret" 0 1 2 3 15
	local uboot_name=${UBOOT_DEB}_${REVISION}_${ARCH}
	rm -rf $uboottempdir/$uboot_name
	mkdir -p $uboottempdir/$uboot_name/usr/lib/{u-boot,$uboot_name} $uboottempdir/$uboot_name/DEBIAN


	# 应用uboot配置文件
	display_alert "Compiler uboot config" "make $CTHREADS $UBOOT_CONFIG" "info"
	eval CCACHE_BASEDIR="$(pwd)" 'make $CTHREADS $UBOOT_CONFIG'

	# 编译uboot
	display_alert "Compiler uboot command" "make $CTHREADS $UBOOT_MAKE_ARGS CROSS_COMPILE=$CCACHE $UBOOT_COMPILER" "info"
	eval CCACHE_BASEDIR="$(pwd)" 'make $CTHREADS $UBOOT_MAKE_ARGS CROSS_COMPILE="$CCACHE $UBOOT_COMPILER"'

	# 如果自定义预构建函数则运行
	[[ $(type -t uboot_custom_postprocess) == function ]] && uboot_custom_postprocess

	# copy files to build directory
	# 复制文件到构建文件夹
	for f in $UBOOT_TARGET_FILES; do
		local f_src
		f_src=$(cut -d':' -f1 <<< "${f}")
		if [[ $f == *:* ]]; then
			local f_dst
			f_dst=$(cut -d':' -f2 <<< "${f}")
		else
			local f_dst
			f_dst=$(basename "${f_src}")
		fi
		[[ ! -f $f_src ]] && exit_with_error "U-boot file not found" "$(basename "${f_src}")"
		cp -v "${f_src}" "$uboottempdir/${uboot_name}/usr/lib/${uboot_name}/${f_dst}"
	done

	# declare -f on non-defined function does not do anything
	cat <<-EOF > "$uboottempdir/${uboot_name}/usr/lib/u-boot/platform_install.sh"
	DIR=/usr/lib/$uboot_name
	$(declare -f write_uboot_platform)
	$(declare -f write_uboot_platform_mtd)
	$(declare -f setup_write_uboot_platform)
	EOF

	# set up control file
	cat <<-EOF > "$uboottempdir/${uboot_name}/DEBIAN/control"
	Package: ${UBOOT_DEB}
	Version: $REVISION
	Architecture: $ARCH
	Maintainer: Embedfire <embedfire@embedfire.com>
	Description: Uboot loader
	EOF

	display_alert "Building package" "${uboot_name}.deb" "info"
	fakeroot dpkg-deb -b -Zxz "$uboottempdir/${uboot_name}" "$uboottempdir/${uboot_name}.deb"
	rm -rf "$uboottempdir/${uboot_name}"
	[[ -n $atftempdir ]] && rm -rf "${atftempdir}"

	[[ ! -f $uboottempdir/${uboot_name}.deb ]] && exit_with_error "Building u-boot package failed"

	mkdir -p ${DEB_DIR}/u-boot/
	rsync --remove-source-files -rq "$uboottempdir/${uboot_name}.deb" "${DEB_DIR}/u-boot/"
	rm -rf "$uboottempdir"
}


# compile_kernel
#
compile_kernel()
{
	cd "${LINUX_DIR}" || exit

	rm -f localversion

	display_alert "Compiler kernel info" "Kernel $LINUX" "info"
	display_alert "Compiler kernel path" "$LINUX_DIR" "info"

	# 应用选择的配置文件
	# display_alert "Compiler kernel config" "make ARCH=$ARCH $LINUX_CONFIG" "info"
	# eval CCACHE_BASEDIR="$(pwd)" 'make ARCH=$ARCH $LINUX_CONFIG'

	display_alert "Copy kernel config" "$LINUX_CONFIG" "info"
	cp -v arch/$ARCH/configs/$LINUX_CONFIG .config
	eval CCACHE_BASEDIR="$(pwd)" \
		'make ARCH=$ARCH CROSS_COMPILE="$CCACHE $LINUX_COMPILER" olddefconfig'

	# 编译内核
	display_alert "Compiler kernel command" "make $CTHREADS ARCH=$ARCH CROSS_COMPILE=$CCACHE $LINUX_COMPILER $KERNEL_IMAGE_TYPE ${KERNEL_EXTRA_TARGETS:-modules dtbs}" "info"
	eval CCACHE_BASEDIR="$(pwd)"  \
		'make $CTHREADS ARCH=$ARCH CROSS_COMPILE="$CCACHE $LINUX_COMPILER" $KERNEL_IMAGE_TYPE ${KERNEL_EXTRA_TARGETS:-modules dtbs}'

	# 编译内核deb包
	display_alert "Compiler kernel deb" "make $CTHREADS ARCH=$ARCH bindeb-pkg LOCALVERSION='' KDEB_PKGVERSION=$REVISION CROSS_COMPILE=$CCACHE $LINUX_COMPILER"  "info"
	eval CCACHE_BASEDIR="$(pwd)" \
		'make $CTHREADS ARCH=$ARCH bindeb-pkg \
		LOCALVERSION="" KDEB_PKGVERSION=$REVISION CROSS_COMPILE="$CCACHE $LINUX_COMPILER" '

	cd .. || exit

	rm -rf ./*.buildinfo ./*.changes
	mkdir -p ${DEB_DIR}/kernel
	rsync --remove-source-files -rq ./*.deb "${DEB_DIR}/kernel/" || exit_with_error "Failed moving kernel DEBs"
}


# compile_firmware
#
compile_firmware()
{
	display_alert "Packaging lbc-firmware" "$HOSTNAME@host" "info"

	local deb_arch deb_version deb_name

	rm -rf ${DEB_DIR}/lbc-firmware
	mkdir -p ${DEB_DIR}/lbc-firmware
	cp -r ${SOURCE_DIR}/lbc-firmware/* ${DEB_DIR}/lbc-firmware

	cd ${DEB_DIR}/lbc-firmware

	deb_arch=$(cat DEBIAN/control | grep Architecture | awk '{print $2}')
	deb_version=$(cat DEBIAN/control | grep Version | awk '{print $2}')
	deb_name=lbc-firmware_${deb_version}_${deb_arch}.deb

	# pack
	display_alert "Building package" "${deb_name}" "info"
	fakeroot dpkg-deb -b -Zxz ./ ../${deb_name}
}


# compile_sunxi_tools
#
compile_sunxi_tools()
{
	# Compile and install only if git commit hash changed
	cd $EXTER/cache/sources/sunxi-tools || exit
	# need to check if /usr/local/bin/sunxi-fexc to detect new Docker containers with old cached sources
	if [[ ! -f .commit_id || $(improved_git rev-parse @ 2>/dev/null) != $(<.commit_id) || ! -f /usr/local/bin/sunxi-fexc ]]; then
		display_alert "Compiling" "sunxi-tools" "info"
		make -s clean >/dev/null
		make -s tools >/dev/null
		mkdir -p /usr/local/bin/
		make install-tools >/dev/null 2>&1
		improved_git rev-parse @ 2>/dev/null > .commit_id
	fi
}
