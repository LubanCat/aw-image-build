#!/bin/bash
#
# Copyright (c) 2013-2021 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

[[ -z $DEST_LANG ]] && DEST_LANG="en_US.UTF-8"			# sl_SI.UTF-8, en_US.UTF-8
[[ -z $ROOTPWD ]] && ROOTPWD="root" # Must be changed @first login
[[ -z $USERNAME ]] && USERNAME="cat"
[[ -z $PASSWORD ]] && PASSWORD="temppwd"
USER_ID=$(stat --format %u build.sh) #chown source and output files
TZDATA=$(cat /etc/timezone) # Timezone for target is taken from host or defined here.
# CTHREADS="-j$(nproc)" # Use all CPU cores for compiling
CTHREADS="-j$(($(nproc)-1))" # Use all CPU cores for compiling
HOST_RELEASE=$(cat /etc/os-release | grep VERSION_CODENAME | cut -d"=" -f2)
[[ -z $HOST_RELEASE ]] && HOST_RELEASE=$(cut -d'/' -f1 /etc/debian_version)
[[ -z $HOST_NAME ]] && HOST_NAME="lubancat" # set hostname to the board
[[ -z "${ROOTFSCACHE_VERSION}" ]] && ROOTFSCACHE_VERSION=11
[[ -z $DOWNLOAD_MIRROR ]] && DOWNLOAD_MIRROR=china

[[ -z $ROOTFS_TYPE ]] && ROOTFS_TYPE=ext4 # default rootfs type is ext4
[[ "ext4 f2fs btrfs xfs nfs" != *$ROOTFS_TYPE* ]] && exit_with_error "Unknown rootfs type" "$ROOTFS_TYPE"

[[ -z $BTRFS_COMPRESSION ]] && BTRFS_COMPRESSION=zlib # default btrfs filesystem compression method is zlib
[[ ! $BTRFS_COMPRESSION =~ zlib|lzo|zstd|none ]] && exit_with_error "Unknown btrfs compression method" "$BTRFS_COMPRESSION"

# Fixed image size is in 1M dd blocks (MiB)
# to get size of block device /dev/sdX execute as root:
# echo $(( $(blockdev --getsize64 /dev/sdX) / 1024 / 1024 ))
[[ "f2fs" == *$ROOTFS_TYPE* && -z $FIXED_IMAGE_SIZE ]] && exit_with_error "Please define FIXED_IMAGE_SIZE"

# Let's set default data if not defined in board configuration above
[[ -z $LOADER_SIZE ]] && LOADER_SIZE=4 # offset to 1st partition (we use 4MiB boundaries by default)
# Default to pdkdf2, this used to be the default with cryptroot <= 2.0, however
# cryptroot 2.1 changed that to Argon2i. Argon2i is a memory intensive
# algorithm which doesn't play well with SBCs (need 1GiB RAM by default !)
# https://gitlab.com/cryptsetup/cryptsetup/-/issues/372
[[ -z $IMAGE_PARTITION_TABLE ]] && IMAGE_PARTITION_TABLE="msdos"
[[ -z $EXTRA_ROOTFS_MIB_SIZE ]] && EXTRA_ROOTFS_MIB_SIZE=0

# single ext4 partition is the default and preferred configuration
#BOOTFS_TYPE=''
[[ ! -f ${EXTER}/config/sources/families/$LINUXFAMILY.conf ]] && \
	exit_with_error "Sources configuration not found" "$LINUXFAMILY"

source "${EXTER}/config/sources/families/${LINUXFAMILY}.conf"

# load architecture defaults
source "${EXTER}/config/sources/${ARCH}.conf"

## Extensions: at this point we've sourced all the config files that will be used,
##             and (hopefully) not yet invoked any extension methods. So this is the perfect
##             place to initialize the extension manager. It will create functions
##             like the 'post_family_config' that is invoked below.
initialize_extension_manager

# Myy : Menu configuration for choosing desktop configurations

show_menu() {
	provided_title=$1
	provided_backtitle=$2
	provided_menuname=$3
	# Myy : I don't know why there's a TTY_Y - 8...
	#echo "Provided title : $provided_title"
	#echo "Provided backtitle : $provided_backtitle"
	#echo "Provided menuname : $provided_menuname"
	#echo "Provided options : " "${@:4}"
	#echo "TTY X: $TTY_X Y: $TTY_Y"
	whiptail --title "${provided_title}" --backtitle "${provided_backtitle}" --notags \
                          --menu "${provided_menuname}" "${TTY_Y}" "${TTY_X}" $((TTY_Y - 8))  \
			  "${@:4}" \
			  3>&1 1>&2 2>&3
}

# Myy : FIXME Factorize
show_select_menu() {
	provided_title=$1
	provided_backtitle=$2
	provided_menuname=$3
	#dialog --stdout --title "${provided_title}" --backtitle "${provided_backtitle}" \
	#--checklist "${provided_menuname}" $TTY_Y $TTY_X $((TTY_Y - 8)) "${@:4}"

	#whiptail --separate-output --title "${provided_title}" --backtitle "${provided_backtitle}" \
	#                  --checklist "${provided_menuname}" "${TTY_Y}" "${TTY_X}" $((TTY_Y - 8))  \
	#		  "${@:4}" \
	#		  3>&1 1>&2 2>&3

	whiptail --title "${provided_title}" --backtitle "${provided_backtitle}" \
	                  --checklist "${provided_menuname}" "${TTY_Y}" "${TTY_X}" $((TTY_Y - 8))  \
			  "${@:4}" \
			  3>&1 1>&2 2>&3
}

# Myy : Once we got a list of selected groups, parse the PACKAGE_LIST inside configuration.sh
DESKTOP_CONFIGS_DIR="${EXTER}/config/desktop/${RELEASE}/environments"
DESKTOP_CONFIG_PREFIX="config_"
DESKTOP_APPGROUPS_DIR="${EXTER}/config/desktop/${RELEASE}/appgroups"

desktop_element_available_for_arch() {
	local desktop_element_path="${1}"
	local targeted_arch="${2}"

	local arch_limitation_file="${1}/only_for"

	echo "Checking if ${desktop_element_path} is available for ${targeted_arch} in ${arch_limitation_file}"
	if [[ -f "${arch_limitation_file}" ]]; then
		grep -- "${targeted_arch}" "${arch_limitation_file}" > /dev/null
		return $?
	else
		return 0
	fi
}

desktop_element_supported() {

	local desktop_element_path="${1}"

	local support_level_filepath="${desktop_element_path}/support"
	if [[ -f "${support_level_filepath}" ]]; then
		local support_level="$(cat "${support_level_filepath}")"
		if [[ "${support_level}" != "supported" && "${EXPERT}" != "yes" ]]; then
			return 65
		fi

		desktop_element_available_for_arch "${desktop_element_path}" "${ARCH}"
		if [[ $? -ne 0 ]]; then
			return 66
		fi
	else
		return 64
	fi

	return 0

}

if [[ $BUILD_OS_TYPE == "desktop" && -z $DESKTOP_ENVIRONMENT ]]; then

	desktop_environments_prepare_menu() {
		for desktop_env_dir in "${DESKTOP_CONFIGS_DIR}/"*; do
			local desktop_env_name=$(basename ${desktop_env_dir})
			local expert_infos=""
			[[ "${EXPERT}" == "yes" ]] && expert_infos="[$(cat "${desktop_env_dir}/support" 2> /dev/null)]"
			desktop_element_supported "${desktop_env_dir}" "${ARCH}" && options+=("${desktop_env_name}" "${desktop_env_name^} desktop environment ${expert_infos}")
		done
	}

	options=()
	desktop_environments_prepare_menu

	if [[ "${options[0]}" == "" ]]; then
		exit_with_error "No desktop environment seems to be available for your board ${BOARD} (ARCH : ${ARCH} - EXPERT : ${EXPERT})"
	fi

	DESKTOP_ENVIRONMENT=$(show_menu "Choose a desktop environment" "$backtitle" "Select the default desktop environment to bundle with this image" "${options[@]}")

	unset options

	if [[ -z "${DESKTOP_ENVIRONMENT}" ]]; then
		exit_with_error "No desktop environment selected..."
	fi

fi

if [[ $BUILD_OS_TYPE == "desktop" ]]; then
	# Expected environment variables :
	# - options
	# - ARCH

	desktop_environment_check_if_valid() {

		local error_msg=""
		desktop_element_supported "${DESKTOP_ENVIRONMENT_DIRPATH}" "${ARCH}"
		local retval=$?

		if [[ ${retval} == 0 ]]; then
			return
		elif [[ ${retval} == 64 ]]; then
			error_msg+="Either the desktop environment ${DESKTOP_ENVIRONMENT} does not exist "
			error_msg+="or the file ${DESKTOP_ENVIRONMENT_DIRPATH}/support is missing"
		elif [[ ${retval} == 65 ]]; then
			error_msg+="Only experts can build an image with the desktop environment \"${DESKTOP_ENVIRONMENT}\", since the Armbian team won't offer any support for it (EXPERT=${EXPERT})"
		elif [[ ${retval} == 66 ]]; then
			error_msg+="The desktop environment \"${DESKTOP_ENVIRONMENT}\" has no packages for your targeted board architecture (BOARD=${BOARD} ARCH=${ARCH}). "
			error_msg+="The supported boards architectures are : "
			error_msg+="$(cat "${DESKTOP_ENVIRONMENT_DIRPATH}/only_for")"
		fi

		# supress error when cache is rebuilding
		[[ -n "$ROOT_FS_CREATE_ONLY" ]] && exit 0

		exit_with_error "${error_msg}"
	}

	DESKTOP_ENVIRONMENT_DIRPATH="${DESKTOP_CONFIGS_DIR}/${DESKTOP_ENVIRONMENT}"

	desktop_environment_check_if_valid
fi

if [[ $BUILD_OS_TYPE == "desktop" && -z $DESKTOP_ENVIRONMENT_CONFIG_NAME ]]; then
	# FIXME Check for empty folders, just in case the current maintainer
	# messed up
	# Note, we could also ignore it and don't show anything in the previous
	# menu, but that hides information and make debugging harder, which I
	# don't like. Adding desktop environments as a maintainer is not a
	# trivial nor common task.

	options=()
	for configuration in "${DESKTOP_ENVIRONMENT_DIRPATH}/${DESKTOP_CONFIG_PREFIX}"*; do
		config_filename=$(basename ${configuration})
		config_name=${config_filename#"${DESKTOP_CONFIG_PREFIX}"}
		options+=("${config_filename}" "${config_name} configuration")
	done

	DESKTOP_ENVIRONMENT_CONFIG_NAME=$(show_menu "Choose the desktop environment config" "$backtitle" "Select the configuration for this environment.\nThese are sourced from ${desktop_environment_config_dir}" "${options[@]}")
	unset options

	if [[ -z $DESKTOP_ENVIRONMENT_CONFIG_NAME ]]; then
		exit_with_error "No desktop configuration selected... Do you really want a desktop environment ?"
	fi
fi

if [[ $BUILD_OS_TYPE == "desktop" ]]; then
	DESKTOP_ENVIRONMENT_PACKAGE_LIST_DIRPATH="${DESKTOP_ENVIRONMENT_DIRPATH}/${DESKTOP_ENVIRONMENT_CONFIG_NAME}"
	DESKTOP_ENVIRONMENT_PACKAGE_LIST_FILEPATH="${DESKTOP_ENVIRONMENT_PACKAGE_LIST_DIRPATH}/packages"
fi

# "-z ${VAR+x}" allows to check for unset variable
# Technically, someone might want to build a desktop with no additional
# appgroups.
if [[ $BUILD_OS_TYPE == "desktop" && -z ${DESKTOP_APPGROUPS_SELECTED+x} ]]; then

	options=()
	for appgroup_path in "${DESKTOP_APPGROUPS_DIR}/"*; do
		appgroup="$(basename "${appgroup_path}")"
		options+=("${appgroup}" "${appgroup^}" off)
	done

	DESKTOP_APPGROUPS_SELECTED=$(\
		show_select_menu \
		"Choose desktop softwares to add" \
		"$backtitle" \
		"Select which kind of softwares you'd like to add to your build" \
		"${options[@]}")

	DESKTOP_APPGROUPS_SELECTED=${DESKTOP_APPGROUPS_SELECTED//\"/}

	unset options
fi

#exit_with_error 'Testing'

# Expected variables
# - aggregated_content
# - potential_paths
# - separator
# Write to variables :
# - aggregated_content
aggregate_content() {
	# 将路径输出到LOG文件
	LOG_OUTPUT_FILE="${LOG_PATH}/potential-paths.log"
	echo -e "Potential paths :" >> "${LOG_OUTPUT_FILE}"
	show_checklist_variables potential_paths
	for filepath in ${potential_paths}; do
		if [[ -f "${filepath}" ]]; then
			echo -e "${filepath/"$EXTER"\//} yes" >> "${LOG_OUTPUT_FILE}"
			aggregated_content+=$(cat "${filepath}")
			aggregated_content+="${separator}"
		fi
	done

	echo "" >> "${LOG_OUTPUT_FILE}"
	unset LOG_OUTPUT_FILE
}

[[ -z $LINUX_CONFIG ]] && LINUX_CONFIG="linux-${LINUXFAMILY}-${BRANCH}_defconfig"

if [[ "$RELEASE" =~ ^(bionic|focal|jammy)$ ]]; then
		DISTRIBUTION="Ubuntu"
	else
		DISTRIBUTION="Debian"
fi

if [[ $? != 0 ]]; then
	exit_with_error "The desktop environment ${DESKTOP_ENVIRONMENT} is not available for your architecture ${ARCH}"
fi

AGGREGATION_SEARCH_ROOT_ABSOLUTE_DIRS="
${EXTER}/config
${EXTER}/config/optional/_any_board/_config
${EXTER}/config/optional/architectures/${ARCH}/_config
${EXTER}/config/optional/families/${LINUXFAMILY}/_config
${EXTER}/config/optional/boards/${BOARD}/_config
"

DEBOOTSTRAP_SEARCH_RELATIVE_DIRS="
server/_all_distributions/debootstrap
server/${RELEASE}/debootstrap
"

CLI_SEARCH_RELATIVE_DIRS="
server/_all_distributions/main
server/${RELEASE}/main
"

PACKAGES_SEARCH_ROOT_ABSOLUTE_DIRS="
${EXTER}/packages
${EXTER}/config/optional/_any_board/_packages
${EXTER}/config/optional/architectures/${ARCH}/_packages
${EXTER}/config/optional/families/${LINUXFAMILY}/_packages
${EXTER}/config/optional/boards/${BOARD}/_packages
"

DESKTOP_ENVIRONMENTS_SEARCH_RELATIVE_DIRS="
desktop/_all_distributions/environments/_all_environments
desktop/_all_distributions/environments/${DESKTOP_ENVIRONMENT}
desktop/_all_distributions/environments/${DESKTOP_ENVIRONMENT}/${DESKTOP_ENVIRONMENT_CONFIG_NAME}
desktop/${RELEASE}/environments/_all_environments
desktop/${RELEASE}/environments/${DESKTOP_ENVIRONMENT}
desktop/${RELEASE}/environments/${DESKTOP_ENVIRONMENT}/${DESKTOP_ENVIRONMENT_CONFIG_NAME}
"

DESKTOP_APPGROUPS_SEARCH_RELATIVE_DIRS="
desktop/_all_distributions/appgroups
desktop/_all_distributions/environments/${DESKTOP_ENVIRONMENT}/appgroups
desktop/${RELEASE}/appgroups
desktop/${RELEASE}/environments/${DESKTOP_ENVIRONMENT}/appgroups
"
# 循环获取所有可能存在所需文件的路径
get_all_potential_paths() {

	local root_dirs="${AGGREGATION_SEARCH_ROOT_ABSOLUTE_DIRS}"
	local rel_dirs="${1}"
	local sub_dirs="${2}"
	local looked_up_subpath="${3}"

	# 拼接地址
	for root_dir in ${root_dirs}; do
		for rel_dir in ${rel_dirs}; do
			for sub_dir in ${sub_dirs}; do
				potential_paths+="${root_dir}/${rel_dir}/${sub_dir}/${looked_up_subpath} "
			done
		done
	done

}

# Environment variables expected :
# - aggregated_content
# Arguments :
# 1. File to look up in each directory
# 2. The separator to add between each concatenated file
# 3. Relative directories paths added to ${3}
# 4. Relative directories paths added to ${4}
#
# The function will basically generate a list of potential paths by
# generating all the potential paths combinations leading to the
# looked up file
# ${AGGREGATION_SEARCH_ROOT_ABSOLUTE_DIRS}/${3}/${4}/${1}
# Then it will concatenate the content of all the available files
# into ${aggregated_content}
#
# TODO :
# ${4} could be removed by just adding the appropriate paths to ${3}
# dynamically for each case
# (debootstrap, cli, desktop environments, desktop appgroups, ...)

aggregate_all_root_rel_sub() {
	local separator="${2}"

	# 拼接后的路径，在get_all_potential_paths中赋值
	local potential_paths=""

	# 循环拼接存在所需文件的路径
	get_all_potential_paths "${3}" "${4}" "${1}"
	aggregate_content
}

aggregate_all_debootstrap() {
	aggregate_all_root_rel_sub "${1}" "${2}" "${DEBOOTSTRAP_SEARCH_RELATIVE_DIRS}" ". config_${BUILD_OS_TYPE}"
}

aggregate_all_cli() {
	aggregate_all_root_rel_sub "${1}" "${2}" "${CLI_SEARCH_RELATIVE_DIRS}" ". config_${BUILD_OS_TYPE}"
}

aggregate_all_desktop() {
	aggregate_all_root_rel_sub "${1}" "${2}" "${DESKTOP_ENVIRONMENTS_SEARCH_RELATIVE_DIRS}" "."
	aggregate_all_root_rel_sub "${1}" "${2}" "${DESKTOP_APPGROUPS_SEARCH_RELATIVE_DIRS}" "${DESKTOP_APPGROUPS_SELECTED}"
}


one_line() {
	local aggregate_func_name="${1}"
	local aggregated_content=""
	shift 1
	$aggregate_func_name "${@}"
	cleanup_list aggregated_content
}

# debootstrap --include=
Debootstrap_Packages="$(one_line aggregate_all_debootstrap "packages" " ")"

# debootstrap --components=
Debootstrap_Components="$(one_line aggregate_all_debootstrap "components" " ")"
Debootstrap_Components="${Debootstrap_Components// /,}"


PACKAGE_LIST="$(one_line aggregate_all_cli "packages" " ")"
PACKAGE_LIST_ADDITIONAL="$(one_line aggregate_all_cli "packages.additional" " ")"

PACKAGE_LIST_UNINSTALL="$(one_line aggregate_all_desktop "packages.uninstall" " ")"
PACKAGE_LIST_UNINSTALL+="$(one_line aggregate_all_cli "packages.uninstall" " ")"


LOG_OUTPUT_FILE="${LOG_PATH}/debootstrap-list.log"
show_checklist_variables "Debootstrap_Packages Debootstrap_Components PACKAGE_LIST PACKAGE_LIST_ADDITIONAL PACKAGE_LIST_UNINSTALL"

# Dependent desktop packages
# Myy : Sources packages from file here

# Myy : FIXME Rename aggregate_all to aggregate_all_desktop
if [[ $BUILD_OS_TYPE == "desktop" ]]; then
	PACKAGE_LIST_DESKTOP+="$(one_line aggregate_all_desktop "packages" " ")"
	echo -e "\nGroups selected ${DESKTOP_APPGROUPS_SELECTED} -> PACKAGES :" >> "${LOG_OUTPUT_FILE}"
	show_checklist_variables PACKAGE_LIST_DESKTOP
fi
unset LOG_OUTPUT_FILE

if [[ $DOWNLOAD_MIRROR == "china" ]] ; then
	DEBIAN_MIRROR='mirrors.ustc.edu.cn/debian'
	DEBIAN_SECURTY='mirrors.ustc.edu.cn/debian-security'
	UBUNTU_MIRROR='mirrors.ustc.edu.cn/ubuntu-ports'
else
	DEBIAN_MIRROR='deb.debian.org/debian'
	DEBIAN_SECURTY='security.debian.org/'
	UBUNTU_MIRROR='ports.ubuntu.com/'
fi

# don't use mirrors that throws garbage on 404
if [[ -z ${ARMBIAN_MIRROR} ]]; then
	while true; do

		ARMBIAN_MIRROR=$(wget -SO- -T 1 -t 1 https://redirect.armbian.com 2>&1 | egrep -i "Location" | awk '{print $2}' | head -1)
		[[ ${ARMBIAN_MIRROR} != *armbian.hosthatch* ]] && break

	done
fi

if [[ $DISTRIBUTION == Ubuntu ]]; then
	APT_MIRROR=$UBUNTU_MIRROR
else
	APT_MIRROR=$DEBIAN_MIRROR
fi

# Build final package list after possible override
PACKAGE_LIST="$PACKAGE_LIST $PACKAGE_LIST_ADDITIONAL"
PACKAGE_MAIN_LIST="$(cleanup_list PACKAGE_LIST)"

[[ $BUILD_OS_TYPE == desktop ]] && PACKAGE_LIST="$PACKAGE_LIST $PACKAGE_LIST_DESKTOP"
PACKAGE_LIST="$(cleanup_list PACKAGE_LIST)"


LOG_OUTPUT_FILE="${LOG_PATH}/debootstrap-list.log"
echo -e "\nVariables after manual configuration" >>$LOG_OUTPUT_FILE
show_checklist_variables "Debootstrap_Components Debootstrap_Packages PACKAGE_LIST PACKAGE_MAIN_LIST"
unset LOG_OUTPUT_FILE

