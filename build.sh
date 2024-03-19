#!/bin/bash
#
# Copyright (c) 2013-2021 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

export TOP_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

EXTER="${TOP_DIR}/external"
EXT_DIR="${TOP_DIR}/external"
SCR_DIR="${TOP_DIR}/scripts"
OUT_DIR="${TOP_DIR}"/out
SOURCE_DIR="${TOP_DIR}"/source

BUILD_DIR="${TOP_DIR}"/build
LOG_PATH=${BUILD_DIR}/debug
DEB_DIR=$BUILD_DIR/debs
SDCARD="${BUILD_DIR}/tmp/rootfs"
MOUNT="${BUILD_DIR}/tmp/mount"
IMG_BUILD_DIR="${BUILD_DIR}/image"

# check for whitespace in ${TOP_DIR} and exit for safety reasons
# 检查 ${TOP_DIR} 是否有空格
grep -q "[[:space:]]" <<<"${TOP_DIR}" && { echo "\"${TOP_DIR}\" contains whitespace. Not supported. Aborting." >&2 ; exit 1 ; }

cd "${TOP_DIR}" || exit

if [[ -f "${SCR_DIR}"/general.sh ]]; then

	# shellcheck source=scripts/general.sh
	# shell 函数
	source "${SCR_DIR}"/general.sh

else

	echo "Error: missing build directory structure"
	exit 255

fi

#  Add the variables needed at the beginning of the path
#在路径的开头添加所需的变量
check_args ()
{

for p in "$@"; do

	case "${p%=*}" in
		LIB_TAG)
			# Take a variable if the branch exists locally
			if [ "${p#*=}" == "$(git branch | \
				gawk -v b="${p#*=}" '{if ( $NF == b ) {print $NF}}')" ]; then
				echo -e "[\e[0;35m warn \x1B[0m] Setting $p"
				eval "$p"
			else
				echo -e "[\e[0;35m warn \x1B[0m] Skip $p setting as LIB_TAG=\"\""
				eval LIB_TAG=""
			fi
			;;
	esac

done

}


check_args "$@"


if [[ "${EUID}" == "0" ]] ; then
	:
else
	display_alert "This script requires root privileges, trying to use sudo" "" "wrn"
	sudo "${TOP_DIR}/build.sh" "$@"
	exit $?
fi

# 是否使用离线模式
if [ "$OFFLINE_WORK" == "yes" ]; then

	echo -e "\n"
	display_alert "* " "You are working offline."
	display_alert "* " "Sources, time and host will not be checked"
	echo -e "\n"
	sleep 3s

else

	# check and install the basic utilities here
	# #在此处检查并安装基础软件包
	prepare_host_basic

fi

# Source the extensions manager library at this point, before sourcing the config.
# This allows early calls to enable_extension(), but initialization proper is done later.
# shellcheck source=scripts/extensions.sh
source "${SCR_DIR}"/extensions.sh


# Script parameters handling
# 脚本参数处理
while [[ "${1}" == *=* ]]; do

	echo "{1}=" ${1}
	parameter=${1%%=*}
	echo parameter $parameter
	value=${1##*=}
	echo value $value
	shift
	display_alert "Command line: setting $parameter to" "${value:-(empty)}" "info"
	eval "$parameter=\"$value\""

done

# shellcheck disable=SC1091
source "${SCR_DIR}"/main.sh


