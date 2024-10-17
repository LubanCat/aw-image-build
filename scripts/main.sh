#!/bin/bash
#
# Copyright (c) 2013-2021 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# Main program
#


cleanup_list() {
	local varname="${1}"
	local list_to_clean="${!varname}"
	list_to_clean="${list_to_clean#"${list_to_clean%%[![:space:]]*}"}"
	list_to_clean="${list_to_clean%"${list_to_clean##*[![:space:]]}"}"
	echo ${list_to_clean}
}


if [[ $(basename "$0") == main.sh ]]; then

	echo "Please use build.sh to start the build process"
	exit 255

fi




# default umask for root is 022 so parent directories won't be group writeable without this
# this is used instead of making the chmod in prepare_host() recursive
umask 002

[[ -z $REVISION ]] && REVISION="unset"

# tty窗口设置
# override stty size
[[ -n $COLUMNS ]] && stty cols $COLUMNS
[[ -n $LINES ]] && stty rows $LINES
TTY_X=$(($(stty size | awk '{print $2}')-6)) 			# determine terminal width
TTY_Y=$(($(stty size | awk '{print $1}')-6)) 			# determine terminal height


# We'll use this title on all menus
backtitle="LubanCat Allwinner building script, http://doc.embedfire.com"
titlestr="Choose an option"

# Warnings mitigation
[[ -z $LANGUAGE ]] && export LANGUAGE="en_US:en"            # set to english if not set
[[ -z $CONSOLE_CHAR ]] && export CONSOLE_CHAR="UTF-8"       # set console to UTF-8 if not set

# Libraries include
# shellcheck source=build-rootfs.sh
source "${SCR_DIR}"/build-rootfs.sh	# build bsae rootfs
# shellcheck source=image-build.sh
source "${SCR_DIR}"/image-build.sh	# creation image
# shellcheck source=image-helpers.sh
source "${SCR_DIR}"/image-helpers.sh	# helpers for OS image building
# shellcheck source=distributions.sh
source "${SCR_DIR}"/distributions.sh	# system specific install
# shellcheck source=desktop.sh
source "${SCR_DIR}"/desktop.sh		# desktop specific install
# shellcheck source=compilation.sh
source "${SCR_DIR}"/compilation.sh	# patching and compilation of kernel, uboot, ATF
# shellcheck source=general.sh
source "${SCR_DIR}"/general.sh		# general functions


# 压缩旧log，并删除超过7天的
mkdir -p ${LOG_PATH}
(cd ${LOG_PATH} && tar -czf logs-"$(<timestamp)".tgz ./*.log) > /dev/null 2>&1
rm -f ${LOG_PATH}/*.log > /dev/null 2>&1
date +"%d_%m_%Y-%H_%M_%S" > ${LOG_PATH}/timestamp

(cd ${LOG_PATH} && find . -name '*.tgz' -mtime +7 -delete) > /dev/null


if [[ $USE_CCACHE != no ]]; then

	#ccache编译加速
	CCACHE=ccache
	export PATH="/usr/lib/ccache:$PATH"
	# private ccache directory to avoid permission issues when using build script with "sudo"
	# see https://ccache.samba.org/manual.html#_sharing_a_cache for alternative solution
	export CCACHE_DIR=$BUILD_DIR/ccache

else

	CCACHE=""

fi

################################################################################


# if BUILD_OPT, BOARD, BRANCH or RELEASE are not set, display selection menu
if [[ -z $BUILD_OPT ]]; then

	options+=("all"	 	 "Build all step")
	options+=("kernel"	 "step1.Build Kernel")
	options+=("u-boot"	 "step2.Build U-boot")
	options+=("rootfs"	 "step3.Build base-rootfs and deb packages")
	options+=("image"	 "step4.Pack image")
	options+=("update"	 "update source repository")
	options+=("clean"	 "clean source/build/out files ")

	menustr="Select to build all | image | rootfs | kernel | u-boot"
	BUILD_OPT=$(whiptail --title "${titlestr}" --backtitle "${backtitle}" --notags \
			  --menu "${menustr}" "${TTY_Y}" "${TTY_X}" $((TTY_Y - 8))  \
			  --cancel-button Exit --ok-button Select "${options[@]}" \
			  3>&1 1>&2 2>&3)

	unset options
	[[ -z $BUILD_OPT ]] && exit_with_error "No option selected"
	[[ $BUILD_OPT == rootfs ]] && ROOT_FS_CREATE_ONLY="yes"
fi


if [[ -z $BOARD ]]; then

	options+=("lubancat-a1"			"Allwinner H618 ")
	options+=("lubancat-a0"			"Allwinner H618 ")

	menustr="Please choose a Board."
	BOARD=$(whiptail --title "${titlestr}" --backtitle "${backtitle}" \
			  --menu "${menustr}" "${TTY_Y}" "${TTY_X}" $((TTY_Y - 8))  \
			  --cancel-button Exit --ok-button Select "${options[@]}" \
			  3>&1 1>&2 2>&3)

	unset options
	[[ -z $BOARD ]] && exit_with_error "No option selected"
fi

# shellcheck source=/dev/null
source "${EXTER}/config/boards/${BOARD}.conf"

[[ -z $KERNEL_TARGET ]] && exit_with_error "Board configuration does not define valid kernel config"

if [[ -z $BRANCH ]]; then

	options=()
	[[ $KERNEL_TARGET == *current* ]] && options+=("current" "Use Allwinner Kernel. Recommended")
	[[ $KERNEL_TARGET == *next* ]] && options+=("next" "Use Mainline Kernel ")

	menustr="Select the target kernel branch\nExact kernel versions depend on selected board"
	# do not display selection dialog if only one kernel branch is available
	if [[ "${#options[@]}" == 2 ]]; then
		BRANCH="${options[0]}"
	else
		BRANCH=$(whiptail --title "${titlestr}" --backtitle "${backtitle}" \
				  --menu "${menustr}" "${TTY_Y}" "${TTY_X}" $((TTY_Y - 8))  \
				  --cancel-button Exit --ok-button Select "${options[@]}" \
				  3>&1 1>&2 2>&3)
	fi
	unset options
	[[ -z $BRANCH ]] && exit_with_error "No kernel branch selected"

fi

if [[ $BUILD_OPT =~ rootfs|image|all && -z $RELEASE ]]; then

	options=()

	distros_options

	menustr="Select the target OS release package base"
	RELEASE=$(whiptail --title "Choose a release package base" --backtitle "${backtitle}" \
			  --menu "${menustr}" "${TTY_Y}" "${TTY_X}" $((TTY_Y - 8))  \
			  --cancel-button Exit --ok-button Select "${options[@]}" \
			  3>&1 1>&2 2>&3)
	#echo "options : ${options}"
	[[ -z $RELEASE ]] && exit_with_error "No release selected"

	unset options
fi

if [[ $BUILD_OPT =~ rootfs|image|all && -z $BUILD_OS_TYPE ]]; then

	# read distribution support status which is written to the board-release file
	set_distribution_status

	options=()
	options+=("server" "Image with console interface")
	options+=("desktop" "Image with desktop environment")

	menustr="Select the target image type"
	BUILD_OS_TYPE=$(whiptail --title "Choose image type" --backtitle "${backtitle}" \
			  --menu "${menustr}" "${TTY_Y}" "${TTY_X}" $((TTY_Y - 8))  \
			  --cancel-button Exit --ok-button Select "${options[@]}" \
			  3>&1 1>&2 2>&3)
	unset options
	[[ -z $BUILD_OS_TYPE ]] && exit_with_error "No option selected"

fi

if [[ $BUILD_OPT == update && -z $GIT_SOURCE_MIRROR ]]; then

	options+=("Gitee" "Open source code repository(China)")
	options+=("Github" "Open source code repository")
	options+=("Gitlab" "For internal development only")

	menustr="Select source mirror"
	GIT_SOURCE_MIRROR=$(whiptail --title "Choose image type" --backtitle "${backtitle}" \
			  --menu "${menustr}" "${TTY_Y}" "${TTY_X}" $((TTY_Y - 8))  \
			  --cancel-button Exit --ok-button Select "${options[@]}" \
			  3>&1 1>&2 2>&3)
	unset options
	[[ -z $GIT_SOURCE_MIRROR ]] && exit_with_error "No option selected"

fi

unset CLEAN_LEVEL
if [[ $BUILD_OPT == clean && -z $CLEAN_LEVEL ]]; then

	options+=("alldeb" "delete all deb packages")
	options+=("debug" "delete all debug logs")
	options+=("rootfs" "delete rootfs cache")
	options+=("build" "delete build dir")
	options+=("images" "delete out dir")
	options+=("sources" "delete sources dir")

	menustr="Select source mirror"
	CLEAN_LEVEL=$(whiptail --title "Choose image type" --backtitle "${backtitle}" \
			  --menu "${menustr}" "${TTY_Y}" "${TTY_X}" $((TTY_Y - 8))  \
			  --cancel-button Exit --ok-button Select "${options[@]}" \
			  3>&1 1>&2 2>&3)
	unset options
	[[ -z $CLEAN_LEVEL ]] && exit_with_error "No option selected"

fi

################################################################################
#shellcheck source=configuration.sh
# 各种变量配置
source "${SCR_DIR}"/configuration.sh

################################################################################

BSP_SERVER_DEB_NAME="${BOARD}-server-bsp"
BSP_SERVER_DEB_FULLNAME="${BSP_SERVER_DEB_NAME}_${REVISION}_${ARCH}"

BSP_DESKTOP_DEB_NAME="${BOARD}-desktop-bsp"
BSP_DESKTOP_PACKAGE_FULLNAME="${BSP_DESKTOP_DEB_NAME}_${REVISION}_${ARCH}"

UBOOT_DEB=${BOARD}-uboot-${BRANCH}
KERNEL_DEB=linux-image-${LINUX}

CHOSEN_DESKTOP=${RELEASE}-desktop-${DESKTOP_ENVIRONMENT}


do_default() {

start=$(date +%s)

# Check and install dependencies, directory structure and settings
# The OFFLINE_WORK variable inside the function
prepare_host

[[ -n $CLEAN_LEVEL ]] && cleaning "$CLEAN_LEVEL"

# fetch_from_repo <url> <dir> <ref> <subdir_flag>
if [[ ${BUILD_OPT} == update ]]; then

	display_alert "Downloading sources" "" "info"

	# u-boot
	fetch_from_repo "$UBOOT_SOURCE" "$UBOOT_DIR" "$UBOOT_BRANCH"

	# kernel
	fetch_from_repo "$LINUX_SOURCE" "$LINUX_DIR" "$LINUX_BRANCH"

	# lbc-firmware
	fetch_from_repo "$GIT_MIRROR/lbc-firmware.git" "${SOURCE_DIR}/lbc-firmware" "branch:master"

	# ATF
	if [[ -n ${ATF_SOURCE} ]]; then
		fetch_from_repo "$ATF_SOURCE" "$ATF_DIR" "$ATF_BRANCH"
	fi

	# fix sourece files owner
	find "$SOURCE_DIR" -user 0 -exec chown -h $USER_ID:$USER_ID {} \;

fi

# 导出环境变量
set > env.txt

################################################################################
# 编译

if [[ $BUILD_OPT == kernel || $BUILD_OPT == all ]]; then

	compile_kernel

	display_alert "Kernel deb path" "${DEB_DIR}" "info"
	display_alert "Kernel deb name" "${KERNEL_DEB}_${REVISION}_${ARCH}.deb" "info"

fi

if [[ $BUILD_OPT == u-boot || $BUILD_OPT == all ]]; then

	[[ -n "${ATF_SOURCE}" ]] && compile_atf

	compile_uboot

	display_alert "Target directory" "${DEB_DIR}/u-boot" "info"
	display_alert "File name" "${UBOOT_DEB}_${REVISION}_${ARCH}.deb" "info"

fi

if [[ $BUILD_OPT == rootfs || $BUILD_OPT == all ]]; then

	create_base_rootfs

	# 创建 lbc-firmware包
	compile_firmware

	# 创建server根文件系统基础配置包
	create_server_bsp_package

	# 创建desktop根文件系统基础配置包
	# [[ -n $RELEASE && $DESKTOP_ENVIRONMENT ]] && create_desktop_bsp_package

	# 创建当前发行版根文件系统配置包
	[[ -n $RELEASE && $DESKTOP_ENVIRONMENT ]] && create_distro_package

fi

if [[ $BUILD_OPT == image || $BUILD_OPT == all ]]; then

	debootstrap_ng

fi

################################################################################
# 构建完成


end=$(date +%s)
runtime=$(((end-start)/60))
display_alert "Runtime" "$runtime min" "info"

display_alert "Repeat Build Options" "sudo ./build.sh ${BUILD_CONFIG} BOARD=${BOARD} BRANCH=${BRANCH} \
$([[ -n $BUILD_OPT ]] && echo "BUILD_OPT=${BUILD_OPT} ")\
$([[ -n $RELEASE ]] && echo "RELEASE=${RELEASE} ")\
$([[ -n $BUILD_OS_TYPE ]] && echo "BUILD_OS_TYPE=${BUILD_OS_TYPE} ")\
$([[ -n $DESKTOP_ENVIRONMENT ]] && echo "DESKTOP_ENVIRONMENT=${DESKTOP_ENVIRONMENT} ")\
$([[ -n $DESKTOP_ENVIRONMENT_CONFIG_NAME  ]] && echo "DESKTOP_ENVIRONMENT_CONFIG_NAME=${DESKTOP_ENVIRONMENT_CONFIG_NAME} ")\
$([[ -n $DESKTOP_APPGROUPS_SELECTED ]] && echo "DESKTOP_APPGROUPS_SELECTED=\"${DESKTOP_APPGROUPS_SELECTED}\" ")\
$([[ -n $DESKTOP_APT_FLAGS_SELECTED ]] && echo "DESKTOP_APT_FLAGS_SELECTED=\"${DESKTOP_APT_FLAGS_SELECTED}\" ")\
$([[ -n $IMAGE_OUT_FILES ]] && echo "IMAGE_OUT_FILES=${IMAGE_OUT_FILES} ")\
$([[ -n $CLEAN_LEVEL ]] && echo "CLEAN_LEVEL=${CLEAN_LEVEL} ")\
" "ext"

} # end of do_default()

if [[ -z $1 ]]; then
	do_default
else
	eval "$@"
fi
