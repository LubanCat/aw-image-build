#!/bin/bash
#
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.


# Functions:
# cleaning
# exit_with_error
# get_package_list_hash
# create_sources_list
# fetch_from_repo
# improved_git
# display_alert
# fingerprint_image
# distro_menu
# wait_for_package_manager
# prepare_host_basic
# prepare_host
# webseed
# download_and_verify
# show_checklist_variables


# cleaning <target>
#
# target: what to clean
# "make" - "make clean" for selected kernel and u-boot
# "debs" - delete output/debs for board&branch
# "ubootdebs" - delete output/debs for uboot&board&branch
# "alldebs" - delete output/debs
# "cache" - delete output/cache
# "oldcache" - remove old output/cache
# "images" - delete output/images
# "sources" - delete output/sources
#
cleaning()
{
	case $1 in
		alldeb) # delete build/debs
		[[ -d "${DEB_DIR}" ]] && display_alert "Cleaning" "${DEB_DIR}" "wrn" && rm -rf ${DEB_DIR}
		;;

		debug) # delete build/debug
		[[ -d $BUILD_DIR/debug ]] && display_alert "Cleaning" "${LOG_PATH}" "wrn" && rm -rf $LOG_PATH
		;;

		rootfs) # delete build/rootfs-base
		[[ -d $BUILD_DIR/rootfs-base ]] && display_alert "Cleaning" "$BUILD_DIR/rootfs-base" "wrn" && rm -rf  $BUILD_DIR/rootfs-base
		;;

		build) # delete build
		[[ -d $BUILD_DIR ]] && display_alert "Cleaning" "$BUILD_DIR" "wrn" && rm -rf  $BUILD_DIR
		;;

		images) # delete out
		[[ -d "${OUT_DIR}" ]] && display_alert "Cleaning" "$OUT_DIR" "wrn" && rm -rf $OUT_DIR
		;;

		sources) # delete sources
		[[ -d $SOURCE_DIR ]] && display_alert "Cleaning" "$SOURCE_DIR" "wrn" && rm -rf $SOURCE_DIR
		;;
	esac
}


# exit_with_error <message> <highlight>
#
# a way to terminate build process
# with verbose error message
#
exit_with_error()
{
	local _file
	local _line=${BASH_LINENO[0]}
	local _function=${FUNCNAME[1]}
	local _description=$1
	local _highlight=$2
	_file=$(basename "${BASH_SOURCE[1]}")
	local stacktrace="$(get_extension_hook_stracktrace "${BASH_SOURCE[*]}" "${BASH_LINENO[*]}")"

	display_alert "ERROR in function $_function" "$stacktrace" "err"
	display_alert "$_description" "$_highlight" "err"
	display_alert "Process terminated" "" "info"

	if [[ "${ERROR_DEBUG_SHELL}" == "yes" ]]; then
		display_alert "MOUNT" "${MOUNT}" "err"
		display_alert "SDCARD" "${SDCARD}" "err"
		display_alert "Here's a shell." "debug it" "err"
		bash < /dev/tty || true
	fi

	# unlock loop device access in case of starvation
	exec {FD}>/var/lock/lbc-debootstrap-losetup
	flock -u "${FD}"

	exit 255
}


# get_package_list_hash
#
# returns md5 hash for current package list and rootfs cache version
get_package_list_hash()
{
	local package_arr exclude_arr
	local list_content
	read -ra package_arr <<< "${Debootstrap_Packages} ${PACKAGE_LIST}"
	read -ra exclude_arr <<< "${PACKAGE_LIST_EXCLUDE}"
	( ( printf "%s\n" "${package_arr[@]}"; printf -- "-%s\n" "${exclude_arr[@]}" ) | sort -u; echo "${1}" ) | md5sum | cut -d' ' -f 1
}


# create_sources_list <release> <basedir>
#
# <release>: buster|bullseye|bookworm|bionic|focal|jammy|hirsute|sid
# <basedir>: path to root directory
#
create_sources_list()
{
	local release=$1
	local basedir=$2
	[[ -z $basedir ]] && exit_with_error "No basedir passed to create_sources_list"

	case $release in
	buster)
	cat <<-EOF > "${basedir}"/etc/apt/sources.list
	deb http://${DEBIAN_MIRROR} $release main contrib non-free
	#deb-src http://${DEBIAN_MIRROR} $release main contrib non-free

	deb http://${DEBIAN_MIRROR} ${release}-updates main contrib non-free
	#deb-src http://${DEBIAN_MIRROR} ${release}-updates main contrib non-free

	deb http://${DEBIAN_MIRROR} ${release}-backports main contrib non-free
	#deb-src http://${DEBIAN_MIRROR} ${release}-backports main contrib non-free

	deb http://${DEBIAN_SECURTY} ${release}/updates main contrib non-free
	#deb-src http://${DEBIAN_SECURTY} ${release}/updates main contrib non-free
	EOF
	;;

	bullseye)
	cat <<-EOF > "${basedir}"/etc/apt/sources.list
	deb https://${DEBIAN_MIRROR} $release main contrib non-free
	#deb-src https://${DEBIAN_MIRROR} $release main contrib non-free

	deb https://${DEBIAN_MIRROR} ${release}-updates main contrib non-free
	#deb-src https://${DEBIAN_MIRROR} ${release}-updates main contrib non-free

	deb https://${DEBIAN_MIRROR} ${release}-backports main contrib non-free
	#deb-src https://${DEBIAN_MIRROR} ${release}-backports main contrib non-free

	deb https://${DEBIAN_SECURTY} ${release}-security main contrib non-free
	#deb-src https://${DEBIAN_SECURTY} ${release}-security main contrib non-free
	EOF
	;;

	bookworm)
	cat <<- EOF > "${basedir}"/etc/apt/sources.list
	deb http://${DEBIAN_MIRROR} $release main contrib non-free non-free-firmware
	#deb-src http://${DEBIAN_MIRROR} $release main contrib non-free non-free-firmware

	deb http://${DEBIAN_MIRROR} ${release}-updates main contrib non-free non-free-firmware
	#deb-src http://${DEBIAN_MIRROR} ${release}-updates main contrib non-free non-free-firmware

	deb http://${DEBIAN_MIRROR} ${release}-backports main contrib non-free non-free-firmware
	#deb-src http://${DEBIAN_MIRROR} ${release}-backports main contrib non-free non-free-firmware

	deb http://${DEBIAN_SECURTY} ${release}-security main contrib non-free non-free-firmware
	#deb-src http://${DEBIAN_SECURTY} ${release}-security main contrib non-free non-free-firmware
	EOF
	;;

	bionic|focal|jammy)
	cat <<-EOF > "${basedir}"/etc/apt/sources.list
	deb http://${UBUNTU_MIRROR} $release main restricted universe multiverse
	#deb-src http://${UBUNTU_MIRROR} $release main restricted universe multiverse

	deb http://${UBUNTU_MIRROR} ${release}-security main restricted universe multiverse
	#deb-src http://${UBUNTU_MIRROR} ${release}-security main restricted universe multiverse

	deb http://${UBUNTU_MIRROR} ${release}-updates main restricted universe multiverse
	#deb-src http://${UBUNTU_MIRROR} ${release}-updates main restricted universe multiverse

	deb http://${UBUNTU_MIRROR} ${release}-backports main restricted universe multiverse
	#deb-src http://${UBUNTU_MIRROR} ${release}-backports main restricted universe multiverse
	EOF
	;;
	esac
}


#
# This function retries Git operations to avoid failure in case remote is borked
# If the git team needs to call a remote server, use this function.
#
improved_git()
{
	local realgit=$(command -v git)
	local retries=3
	local delay=10
	local count=1
	while [ $count -lt $retries ]; do
		$realgit "$@"
		if [[ $? -eq 0 || -f .git/index.lock ]]; then
			retries=0
			break
		fi
	let count=$count+1
	sleep $delay
	done
}


# fetch_from_repo <url> <directory> <ref> <ref_subdir>
# <url>: remote repository URL
# <directory>: local directory; subdir for branch/tag will be created
# <ref>:
#	branch:name
#	tag:name
#	head(*)
#	commit:hash
#
# *: Implies ref_subdir=no
#
# <ref_subdir>: "yes" to create subdirectory for tag or branch name
#
fetch_from_repo()
{
	local url=$1
	local dir=$2
	local ref=$3
	local ref_subdir=$4

	# Set GitHub mirror before anything else touches $url
	# url=${url//'https://github.com/'/$GITHUB_SOURCE'/'}

	echo git url $url
	# The 'offline' variable must always be set to 'true' or 'false'
	if [ "$OFFLINE_WORK" == "yes" ]; then
		local offline=true
	else
		local offline=false
	fi

	[[ -z $ref || ( $ref != tag:* && $ref != branch:* && $ref != head && $ref != commit:* ) ]] && exit_with_error "Error in configuration"
	local ref_type=${ref%%:*}
	if [[ $ref_type == head ]]; then
		local ref_name=HEAD
	else
		local ref_name=${ref##*:}
	fi

	display_alert "Checking git sources" "$dir $ref_name" "info"

	# get default remote branch name without cloning
	# local ref_name=$(git ls-remote --symref $url HEAD | grep -o 'refs/heads/\S*' | sed 's%refs/heads/%%')
	# for git:// protocol comparing hashes of "git ls-remote -h $url" and "git ls-remote --symref $url HEAD" is needed

	if [[ $ref_subdir == yes ]]; then
		local workdir=$dir/$ref_name
	else
		local workdir=$dir
	fi

	mkdir -p "${workdir}" 2>/dev/null || \
		exit_with_error "No path or no write permission" "${workdir}"

	cd "${workdir}" || exit

	# check if existing remote URL for the repo or branch does not match current one
	# may not be supported by older git versions
	#  Check the folder as a git repository.
	#  Then the target URL matches the local URL.

	if [[ "$(git rev-parse --git-dir 2>/dev/null)" == ".git" && \
		  "$url" != *"$(git remote get-url origin | sed 's/^.*@//' | sed 's/^.*\/\///' 2>/dev/null)" ]]; then
		display_alert "Remote URL does not match, removing existing local copy"
		rm -rf .git ./*
	fi

	if [[ "$(git rev-parse --git-dir 2>/dev/null)" != ".git" ]]; then
		display_alert "Creating local copy"
		git init -q .
		git remote add origin "${url}"
		# Here you need to upload from a new address
		offline=false
	fi

	local changed=false

	# when we work offline we simply return the sources to their original state
	if ! $offline; then
		local local_hash
		local_hash=$(git rev-parse @ 2>/dev/null)

		case $ref_type in
			branch)
			# TODO: grep refs/heads/$name
			local remote_hash
			remote_hash=$(improved_git ls-remote -h "${url}" "$ref_name" | head -1 | cut -f1)
			[[ -z $local_hash || "${local_hash}" != "${remote_hash}" ]] && changed=true
			;;

			tag)
			local remote_hash
			remote_hash=$(improved_git ls-remote -t "${url}" "$ref_name" | cut -f1)
			if [[ -z $local_hash || "${local_hash}" != "${remote_hash}" ]]; then
				remote_hash=$(improved_git ls-remote -t "${url}" "$ref_name^{}" | cut -f1)
				[[ -z $remote_hash || "${local_hash}" != "${remote_hash}" ]] && changed=true
			fi
			;;

			head)
			local remote_hash
			remote_hash=$(improved_git ls-remote "${url}" HEAD | cut -f1)
			[[ -z $local_hash || "${local_hash}" != "${remote_hash}" ]] && changed=true
			;;

			commit)
			[[ -z $local_hash || $local_hash == "@" ]] && changed=true
			;;
		esac

	fi # offline

	if [[ $changed == true ]]; then

		# remote was updated, fetch and check out updates
		display_alert "Fetching updates"
		case $ref_type in
			branch) improved_git fetch --depth 200 origin "${ref_name}" ;;
			tag) improved_git fetch --depth 200 origin tags/"${ref_name}" ;;
			head) improved_git fetch --depth 200 origin HEAD ;;
		esac

		# commit type needs support for older git servers that doesn't support fetching id directly
		if [[ $ref_type == commit ]]; then

			improved_git fetch --depth 200 origin "${ref_name}"

			# cover old type
			if [[ $? -ne 0 ]]; then
				display_alert "Commit checkout not supported on this repository. Doing full clone." "" "wrn"
				improved_git pull
				git checkout -fq "${ref_name}"
				display_alert "Checkout out to" "$(git --no-pager log -2 --pretty=format:"$ad%s [%an]" | head -1)" "info"
			else
				display_alert "Checking out"
				git checkout -f -q FETCH_HEAD
				git clean -qdf
			fi
		else
			display_alert "Checking out"
			git checkout -f -q FETCH_HEAD
			git clean -qdf
		fi
	elif [[ -n $(git status -uno --porcelain --ignore-submodules=all) ]]; then
		# working directory is not clean
		display_alert " Cleaning .... " "$(git status -s | wc -l) files"

		# Return the files that are tracked by git to the initial state.
		git checkout -f -q HEAD

		# Files that are not tracked by git and were added
		# when the patch was applied must be removed.
		git clean -qdf
	else
		# working directory is clean, nothing to do
		display_alert "Up to date"
	fi

	if [[ -f .gitmodules ]]; then
		display_alert "Updating submodules" "" "ext"
		# FML: http://stackoverflow.com/a/17692710
		for i in $(git config -f .gitmodules --get-regexp path | awk '{ print $2 }'); do
			cd "${workdir}" || exit
			local surl sref
			surl=$(git config -f .gitmodules --get "submodule.$i.url")
			sref=$(git config -f .gitmodules --get "submodule.$i.branch")
			if [[ -n $sref ]]; then
				sref="branch:$sref"
			else
				sref="head"
			fi
			fetch_from_repo "$surl" "$workdir/$i" "$sref"
		done
	fi
} #############################################################################

#--------------------------------------------------------------------------------------------------------------------------------
# Let's have unique way of displaying alerts
#--------------------------------------------------------------------------------------------------------------------------------
display_alert()
{
	# log function parameters to install.log
	# [[ -n "${BUILD_DIR}" ]] && echo "Displaying message: $@"

	local tmp=""
	[[ -n $2 ]] && tmp="[\e[0;33m $2 \x1B[0m]"

	case $3 in
		err)
		echo -e "[\e[0;31m error \x1B[0m] $1 $tmp"
		;;

		wrn)
		echo -e "[\e[0;35m warn \x1B[0m] $1 $tmp"
		;;

		ext)
		echo -e "[\e[0;32m o.k. \x1B[0m] \e[1;32m$1\x1B[0m $tmp"
		;;

		info)
		echo -e "[\e[0;32m info \x1B[0m] \e[0;32m$1\x1B[0m $tmp"
		;;

		*)
		echo -e "[\e[0;32m .... \x1B[0m] $1 $tmp"
		;;
	esac
}

#--------------------------------------------------------------------------------------------------------------------------------
# fingerprint_image <out_txt_file> [image_filename]
# Saving build summary to the image
#--------------------------------------------------------------------------------------------------------------------------------
fingerprint_image()
{
	cat <<-EOF > "${1}"
	--------------------------------------------------------------------------------
	Title:			${BOARD^} $DISTRIBUTION $RELEASE $BRANCH $REVISION
	Kernel:			Linux $VER
	Build date:		$(date +'%d.%m.%Y')
	Maintainer:		Embedfire <embedfire@embedfire.com>

	--------------------------------------------------------------------------------
	Partitioning configuration: $IMAGE_PARTITION_TABLE offset: $LOADER_SIZE
	Boot partition type: ${BOOTFS_TYPE:-(none)} ${BOOTSIZE:+"(${BOOTSIZE} MB)"}
	Root partition type: $ROOTFS_TYPE ${FIXED_IMAGE_SIZE:+"(${FIXED_IMAGE_SIZE} MB)"}
	CPU configuration: $CPUMIN - $CPUMAX with $GOVERNOR

	--------------------------------------------------------------------------------

	EOF
}


DISTRIBUTIONS_DESC_DIR="external/config/distributions"

function distro_menu ()
{
# create a select menu for choosing a distribution based EXPERT status

	local distrib_dir="${1}"

	if [[ -d "${distrib_dir}" && -f "${distrib_dir}/support" ]]; then
		local support_level="$(cat "${distrib_dir}/support")"
		if [[ "${support_level}" != "supported" && $EXPERT != "yes" ]]; then
			:
		else
			local distro_codename="$(basename "${distrib_dir}")"
			local distro_fullname="$(cat "${distrib_dir}/name")"
			local expert_infos=""
			[[ $EXPERT == "yes" ]] && expert_infos="(${support_level})"

			if [[ "${BRANCH}" == "current" ]]; then
				DISTRIB_TYPE="${DISTRIB_TYPE_CURRENT}"
				[[ -z "${DISTRIB_TYPE_CURRENT}" ]] && DISTRIB_TYPE="bullseye bookworm focal jammy"
			elif [[ "${BRANCH}" == "next" ]]; then
				DISTRIB_TYPE="${DISTRIB_TYPE_NEXT}"
				[[ -z "${DISTRIB_TYPE_NEXT}" ]] && DISTRIB_TYPE="bullseye bookworm focal jammy"
			fi

			if [[ "${DISTRIB_TYPE}" =~ "${distro_codename}" ]]; then
				options+=("${distro_codename}" "${distro_fullname} ${expert_infos}")
			fi
		fi
	fi
}

function distros_options() {
	for distrib_dir in "${DISTRIBUTIONS_DESC_DIR}/"*; do
		distro_menu "${distrib_dir}"
	done
}

function set_distribution_status() {

	local distro_support_desc_filepath="${TOP_DIR}/${DISTRIBUTIONS_DESC_DIR}/${RELEASE}/support"
	if [[ ! -f "${distro_support_desc_filepath}" ]]; then
		exit_with_error "Distribution ${distribution_name} does not exist"
	else
		DISTRIBUTION_STATUS="$(cat "${distro_support_desc_filepath}")"
	fi

	[[ "${DISTRIBUTION_STATUS}" != "supported" ]]  && exit_with_error "${RELEASE} is unsupported"

}



# wait_for_package_manager
#
# * installation will break if we try to install when package manager is running
#
wait_for_package_manager()
{
	# exit if package manager is running in the back
	while true; do
		if [[ "$(fuser /var/lib/dpkg/lock 2>/dev/null; echo $?)" != 1 && "$(fuser /var/lib/dpkg/lock-frontend 2>/dev/null; echo $?)" != 1 ]]; then
				display_alert "Package manager is running in the background." "Please wait! Retrying in 30 sec" "wrn"
				sleep 30
			else
				break
		fi
	done
}

# Installing packages in host system.
# The function accepts four optional parameters:
# autoupdate - If the installation list is not empty then update first.
# upgrade, clean - the same name for apt
# verbose - detailed log for the function
#
# list="pkg1 pkg2 pkg3 pkgbadname pkg-1.0 | pkg-2.0 pkg5 (>= 9)"
# install_pkg_deb upgrade verbose $list
# or
# install_pkg_deb autoupdate $list
#
# If the package has a bad name, we will see it in the log file.
# If there is an LOG_OUTPUT_FILE variable and it has a value as
# the full real path to the log file, then all the information will be there.
#
# The LOG_OUTPUT_FILE variable must be defined in the calling function
# before calling the install_pkg_deb function and unset after.
#
install_pkg_deb ()
{
	local list=""
	local for_install
	local need_autoup=false
	local need_upgrade=false
	local need_clean=false
	local need_verbose=false
	local _line=${BASH_LINENO[0]}
	local _function=${FUNCNAME[1]}
	local _file=$(basename "${BASH_SOURCE[1]}")
	local tmp_file=$(mktemp /tmp/install_log_XXXXX)
	export DEBIAN_FRONTEND=noninteractive

	list=$(
	for p in $*;do
		case $p in
			autoupdate) need_autoup=true; continue ;;
			upgrade) need_upgrade=true; continue ;;
			clean) need_clean=true; continue ;;
			verbose) need_verbose=true; continue ;;
			\||\(*|*\)) continue ;;
		esac
		echo " $p"
	done
	)

	log_file="${LOG_PATH}/install.log"

	# This is necessary first when there is no apt cache.
	if $need_upgrade; then
		apt-get -q update || echo "apt cannot update" >>$tmp_file
		apt-get -y upgrade || echo "apt cannot upgrade" >>$tmp_file
	fi

	# If the package is not installed, check the latest
	# up-to-date version in the apt cache.
	# Exclude bad package names and send a message to the log.
	for_install=$(
	for p in $list;do
	  if $(dpkg-query -W -f '${db:Status-Abbrev}' $p |& awk '/ii/{exit 1}');then
		apt-cache  show $p -o APT::Cache::AllVersions=no |& \
		awk -v p=$p -v tmp_file=$tmp_file \
		'/^Package:/{print $2} /^E:/{print "Bad package name: ",p >>tmp_file}'
	  fi
	done
	)

	# This information should be logged.
	if [ -s $tmp_file ]; then
		echo -e "\nInstalling packages in function: $_function" "[$_file:$_line]" \
		>>$log_file
		echo -e "\nIncoming list:" >>$log_file
		printf "%-30s %-30s %-30s %-30s\n" $list >>$log_file
		echo "" >>$log_file
		cat $tmp_file >>$log_file
	fi

	if [ -n "$for_install" ]; then
		if $need_autoup; then
			apt-get -q update
			apt-get -y upgrade
		fi
		apt-get install -qq -y --no-install-recommends $for_install
		echo -e "\nPackages installed:" >>$log_file
		dpkg-query -W \
		  -f '${binary:Package;-27} ${Version;-23}\n' \
		  $for_install >>$log_file

	fi

	# We will show the status after installation all listed
	if $need_verbose; then
		echo -e "\nstatus after installation:" >>$log_file
		dpkg-query -W \
		  -f '${binary:Package;-27} ${Version;-23} [ ${Status} ]\n' \
		  $list >>$log_file
	fi

	if $need_clean;then apt-get clean; fi
	rm $tmp_file
}


# check_pkg_version
#
# * check host packages version
#
check_pkg_version()
{
	if [[ -z $(dpkg -l debootstrap | grep 1.0.134) ]]; then
		wget http://ftp.cn.debian.org/debian/pool/main/d/debootstrap/debootstrap_1.0.134_all.deb
		dpkg -i debootstrap_1.0.134_all.deb
	fi

	if [[ -z $(dpkg -l debian-archive-keyring | grep 2023.4) ]]; then
		wget http://ftp.cn.debian.org/debian/pool/main/d/debian-archive-keyring/debian-archive-keyring_2023.4_all.deb
		sudo dpkg -i debian-archive-keyring_2023.4_all.deb
	fi
}


# prepare_host_basic
#
# * installs only basic packages
#
prepare_host_basic()
{

	# command:package1 package2 ...
	# list of commands that are neeeded:packages where this command is
	local check_pack install_pack
	local checklist=(
			"whiptail:whiptail"
			"dialog:dialog"
			"fuser:psmisc"
			"getfacl:acl"
			"uuid:uuid uuid-runtime"
			"curl:curl"
			"gpg:gnupg"
			"gawk:gawk"
			"git:git"
			)

	for check_pack in "${checklist[@]}"; do
	        if ! which ${check_pack%:*} >/dev/null; then local install_pack+=${check_pack#*:}" "; fi
	done

	if [[ -n $install_pack ]]; then
		display_alert "Installing basic packages" "$install_pack"
		sudo bash -c "apt-get -qq update && apt-get install -qq -y --no-install-recommends $install_pack"
	fi

}




# prepare_host
#
# * checks and installs necessary packages
# * creates directory structure
# * changes system settings
#
prepare_host()
{
	display_alert "Preparing" "host" "info"

	# The 'offline' variable must always be set to 'true' or 'false'
	if [ "$OFFLINE_WORK" == "yes" ]; then
		local offline=true
	else
		local offline=false
	fi

	# wait until package manager finishes possible system maintanace
	wait_for_package_manager

	# fix for Locales settings
	if ! grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen; then
		sudo sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
		sudo locale-gen
	fi

	export LC_ALL="en_US.UTF-8"

	# packages list for host
	# NOTE: please sync any changes here with the Vagrantfile

	local hostdeps="acl aptly aria2 bc binfmt-support bison btrfs-progs       \
	build-essential  ca-certificates ccache cpio cryptsetup curl              \
	debian-archive-keyring debian-keyring debootstrap device-tree-compiler    \
	dialog dirmngr dosfstools dwarves f2fs-tools fakeroot flex gawk           \
	gcc-arm-linux-gnueabihf gdisk gpg imagemagick jq kmod libbison-dev \
	libc6-dev-armhf-cross libelf-dev libfdt-dev libfile-fcntllock-perl        \
	libfl-dev liblz4-tool libncurses-dev libpython2.7-dev libssl-dev          \
	libusb-1.0-0-dev linux-base locales lzop ncurses-base ncurses-term        \
	nfs-kernel-server ntpdate p7zip-full parted patchutils pigz pixz          \
	pkg-config pv python3-dev python3-distutils qemu-user-static rsync swig   \
	systemd-container u-boot-tools udev unzip uuid-dev wget whiptail zip      \
	zlib1g-dev"

	if [[ $(dpkg --print-architecture) == amd64 ]]; then

		hostdeps+=" distcc lib32ncurses-dev lib32stdc++6 libc6-i386"
		grep -q i386 <(dpkg --print-foreign-architectures) || dpkg --add-architecture i386

	else

		exit_with_error "Running this tool on non x86_64 build host is not supported"

	fi

	# Add support for Ubuntu 20.04, 21.04 and Mint 20.x
	if [[ $HOST_RELEASE =~ ^(focal|hirsute|jammy|ulyana|ulyssa|bullseye|bookworm|uma)$ ]]; then
		hostdeps+=" python2 python3"
		ln -fs /usr/bin/python2.7 /usr/bin/python2
		ln -fs /usr/bin/python2.7 /usr/bin/python
	else
		hostdeps+=" python libpython-dev"
	fi

	display_alert "Build host OS release" "${HOST_RELEASE:-(unknown)}" "info"

	# Ubuntu 21.04.x (Hirsute) x86_64 is the only fully supported host OS release
	# Using Docker/VirtualBox/Vagrant is the only supported way to run the build script on other Linux distributions
	#
	# NO_HOST_RELEASE_CHECK overrides the check for a supported host system
	# Disable host OS check at your own risk. Any issues reported with unsupported releases will be closed without discussion
	if [[ -z $HOST_RELEASE || "focal jammy" != *"$HOST_RELEASE"* ]]; then
		if [[ $NO_HOST_RELEASE_CHECK == yes ]]; then
			display_alert "You are running on an unsupported system" "${HOST_RELEASE:-(unknown)}" "wrn"
			display_alert "Do not report any errors, warnings or other issues encountered beyond this point" "" "wrn"
		else
			exit_with_error "It seems you run an unsupported build system: ${HOST_RELEASE:-(unknown)}"
		fi
	fi

	if grep -qE "(Microsoft|WSL)" /proc/version; then
		exit_with_error "Windows subsystem for Linux is not a supported build environment"
	fi

	if systemd-detect-virt -q -c; then
		display_alert "Running in container" "$(systemd-detect-virt)" "info"

		CONTAINER_COMPAT=yes
	fi


	# Skip verification if you are working offline
	if ! $offline; then

		display_alert "Installing build dependencies"
		# don't prompt for apt cacher selection
		sudo echo "apt-cacher-ng    apt-cacher-ng/tunnelenable      boolean false" | sudo debconf-set-selections

		install_pkg_deb "autoupdate $hostdeps"

		check_pkg_version

		update-ccache-symlinks

		if [[ $(dpkg --print-architecture) == amd64 ]]; then

			# bind mount toolchain if defined
			if [[ -d "${ARMBIAN_CACHE_TOOLCHAIN_PATH}" ]]; then
				mountpoint -q "${TOP_DIR}"/cache/toolchain && umount -l "${TOP_DIR}"/cache/toolchain
				mount --bind "${ARMBIAN_CACHE_TOOLCHAIN_PATH}" "${TOP_DIR}"/cache/toolchain
			fi

			display_alert "Checking for external GCC compilers" "" "info"
			# download external Linaro compiler and missing special dependencies since they are needed for certain sources

			local toolchains=(
				# "gcc-linaro-aarch64-none-elf-4.8-2013.11_linux.tar.xz"
				# "gcc-linaro-arm-none-eabi-4.8-2014.04_linux.tar.xz"
				# "gcc-linaro-arm-linux-gnueabihf-4.8-2014.04_linux.tar.xz"
				# "gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabi.tar.xz"
				# "gcc-linaro-4.9.4-2017.01-x86_64_aarch64-linux-gnu.tar.xz"
				# "gcc-linaro-5.5.0-2017.10-x86_64_arm-linux-gnueabihf.tar.xz"
				"gcc-linaro-7.4.1-2019.02-x86_64_arm-linux-gnueabi.tar.xz"
				# "gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu.tar.xz"
				# "gcc-arm-9.2-2019.12-x86_64-arm-none-linux-gnueabihf.tar.xz"
				"gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu.tar.xz"
				# "gcc-arm-11.2-2022.02-x86_64-arm-none-linux-gnueabihf.tar.xz"
				"gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu.tar.xz"
				)

			for toolchain in ${toolchains[@]}; do
				download_and_verify "_toolchain" "${toolchain##*/}"
			done

			rm -rf $TOP_DIR/toolchains/*.tar.xz*
			local existing_dirs=( $(ls -1 $TOP_DIR/toolchains) )
			for dir in ${existing_dirs[@]}; do
				local found=no
				for toolchain in ${toolchains[@]}; do
					local filename=${toolchain##*/}
					local dirname=${filename//.tar.xz}
					[[ $dir == $dirname ]] && found=yes
				done
				if [[ $found == no ]]; then
					display_alert "Removing obsolete toolchain" "$dir"
					rm -rf $TOP_DIR/toolchains/$dir
				fi
			done
		fi
	fi # check offline

	# enable arm binary format so that the cross-architecture chroot environment will work
	if [[ $BUILD_OPT == "image" || $BUILD_OPT == "rootfs" || $BUILD_OPT == "all"  ]]; then
		modprobe -q binfmt_misc
		mountpoint -q /proc/sys/fs/binfmt_misc/ || mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc
		if [[ "$(arch)" != "aarch64" ]]; then
			test -e /proc/sys/fs/binfmt_misc/qemu-arm || update-binfmts --enable qemu-arm
			test -e /proc/sys/fs/binfmt_misc/qemu-aarch64 || update-binfmts --enable qemu-aarch64
		fi
	fi

	# check free space (basic)
	local freespace=$(findmnt --target "${TOP_DIR}" -n -o AVAIL -b 2>/dev/null) # in bytes
	if [[ -n $freespace && $(( $freespace / 1073741824 )) -lt 10 ]]; then
		display_alert "Low free space left" "$(( $freespace / 1073741824 )) GiB" "wrn"
		# pause here since dialog-based menu will hide this message otherwise
		echo -e "Press \e[0;33m<Ctrl-C>\x1B[0m to abort compilation, \e[0;33m<Enter>\x1B[0m to ignore and continue"
		read
	fi
}


function webseed ()
{
	# list of mirrors that host our files
	unset text
	# Hardcoded to EU mirrors since
	local CCODE=$(curl -s redirect.armbian.com/geoip | jq '.continent.code' -r)
	WEBSEED=($(curl -s https://redirect.armbian.com/mirrors | jq -r '.'${CCODE}' | .[] | values'))
	# aria2 simply split chunks based on sources count not depending on download speed
	# when selecting china mirrors, use only China mirror, others are very slow there
	if [[ $DOWNLOAD_MIRROR == china ]]; then
		WEBSEED=(
		https://mirrors.tuna.tsinghua.edu.cn/armbian-releases/
		)
	elif [[ $DOWNLOAD_MIRROR == bfsu ]]; then
		WEBSEED=(
		https://mirrors.bfsu.edu.cn/armbian-releases/
		)
	fi
	for toolchain in ${WEBSEED[@]}; do
		text="${text} ${toolchain}${1}"
	done
	text="${text:1}"
	echo "${text}"
}


download_and_verify()
{
	local remotedir=$1
	local filename=$2
	local localdir=$TOP_DIR/toolchains
	local dirname=${filename//.tar.xz}

	mkdir -p ${localdir}

	if [[ $DOWNLOAD_MIRROR == china ]]; then
		local server="https://mirrors.tuna.tsinghua.edu.cn/armbian-releases/"
	elif [[ $DOWNLOAD_MIRROR == bfsu ]]; then
		local server="https://mirrors.bfsu.edu.cn/armbian-releases/"
	else
		local server=${ARMBIAN_MIRROR}
	fi

	if [[ -f ${localdir}/${dirname}/.download-complete ]]; then
		return
	fi

	# switch to china mirror if US timeouts
	timeout 10 curl --head --fail --silent ${server}${remotedir}/${filename} 2>&1 >/dev/null
	if [[ $? -ne 7 && $? -ne 22 && $? -ne 0 ]]; then
		display_alert "Timeout from $server" "retrying" "info"
		server="https://mirrors.tuna.tsinghua.edu.cn/armbian-releases/"

		# switch to another china mirror if tuna timeouts
		timeout 10 curl --head --fail --silent ${server}${remotedir}/${filename} 2>&1 >/dev/null
		if [[ $? -ne 7 && $? -ne 22 && $? -ne 0 ]]; then
			display_alert "Timeout from $server" "retrying" "info"
			server="https://mirrors.bfsu.edu.cn/armbian-releases/"
		fi
	fi


	# check if file exists on remote server before running aria2 downloader
	[[ ! `timeout 10 curl --head --fail --silent ${server}${remotedir}/${filename}` ]] && return

	cd "${localdir}" || exit

	# use local control file
	if [[ -f "${EXTER}"/config/torrents/${filename}.asc ]]; then
		local torrent="${EXTER}"/config/torrents/${filename}.torrent
		ln -sf "${EXTER}/config/torrents/${filename}.asc" "${localdir}/${filename}.asc"
	elif [[ ! `timeout 10 curl --head --fail --silent "${server}${remotedir}/${filename}.asc"` ]]; then
		return
	else
		# download control file
		local torrent=${server}$remotedir/${filename}.torrent
		aria2c --download-result=hide --disable-ipv6=true --summary-interval=0 --console-log-level=error --auto-file-renaming=false \
		--continue=false --allow-overwrite=true --dir="${localdir}" ${server}${remotedir}/${filename}.asc $(webseed "$remotedir/${filename}.asc") -o "${filename}.asc"
		[[ $? -ne 0 ]] && display_alert "Failed to download control file" "" "wrn"
	fi

	# direct download if torrent fails
	if [[ ! -f "${localdir}/${filename}.complete" ]]; then
		if [[ ! `timeout 10 curl --head --fail --silent ${server}${remotedir}/${filename} 2>&1 >/dev/null` ]]; then
			display_alert "downloading using http(s) network" "$filename"
			aria2c --download-result=hide --rpc-save-upload-metadata=false --console-log-level=error \
			--dht-file-path="${TOP_DIR}"/cache/.aria2/dht.dat --disable-ipv6=true --summary-interval=0 --auto-file-renaming=false --dir="${localdir}" ${server}${remotedir}/${filename} $(webseed "${remotedir}/${filename}") -o "${filename}"
			# mark complete
			[[ $? -eq 0 ]] && touch "${localdir}/${filename}.complete" && echo ""

		fi
	fi

	if [[ -f ${localdir}/${filename}.asc ]]; then

		if grep -q 'BEGIN PGP SIGNATURE' "${localdir}/${filename}.asc"; then

			if [[ ! -d $EXTER/cache/.gpg ]]; then
				mkdir -p $EXTER/cache/.gpg
				chmod 700 $EXTER/cache/.gpg
				touch $EXTER/cache/.gpg/gpg.conf
				chmod 600 $EXTER/cache/.gpg/gpg.conf
			fi

			# Verify archives with Linaro and Armbian GPG keys

			if [ x"" != x"${http_proxy}" ]; then
				(gpg --homedir "${EXTER}"/cache/.gpg --no-permission-warning --list-keys 8F427EAF \
				 || gpg --homedir "${EXTER}"/cache/.gpg --no-permission-warning \
				--keyserver hkp://keyserver.ubuntu.com:80 --keyserver-options http-proxy="${http_proxy}" \
				--recv-keys 8F427EAF )

				(gpg --homedir "${EXTER}"/cache/.gpg --no-permission-warning --list-keys 9F0E78D5 \
				|| gpg --homedir "${EXTER}"/cache/.gpg --no-permission-warning \
				--keyserver hkp://keyserver.ubuntu.com:80 --keyserver-options http-proxy="${http_proxy}" \
				--recv-keys 9F0E78D5 )
			else
				(gpg --homedir "${EXTER}"/cache/.gpg --no-permission-warning --list-keys 8F427EAF \
				 || gpg --homedir "${EXTER}"/cache/.gpg --no-permission-warning \
				--keyserver hkp://keyserver.ubuntu.com:80 \
				--recv-keys 8F427EAF )

				(gpg --homedir "${EXTER}"/cache/.gpg --no-permission-warning --list-keys 9F0E78D5 \
				|| gpg --homedir "${EXTER}"/cache/.gpg --no-permission-warning \
				--keyserver hkp://keyserver.ubuntu.com:80 \
				--recv-keys 9F0E78D5 )
			fi

			gpg --homedir "${EXTER}"/cache/.gpg --no-permission-warning --verify \
			--trust-model always -q "${localdir}/${filename}.asc"
			[[ ${PIPESTATUS[0]} -eq 0 ]] && verified=true && display_alert "Verified" "PGP" "info"

		else

			md5sum -c --status "${localdir}/${filename}.asc" && verified=true && display_alert "Verified" "MD5" "info"

		fi

		if [[ $verified == true ]]; then
			if [[ "${filename:(-6)}" == "tar.xz" ]]; then

				display_alert "decompressing"
				pv -p -b -r -c -N "[ .... ] ${filename}" "${filename}" | xz -dc | tar xp --xattrs --no-same-owner --overwrite
				[[ $? -eq 0 ]] && touch "${localdir}/${dirname}/.download-complete"
			fi
		else
			exit_with_error "verification failed"
		fi

	fi
}


# is a formatted output of the values of variables
# from the list at the place of the function call.
#
# The LOG_OUTPUT_FILE variable must be defined in the calling function
# before calling the `show_checklist_variables` function and unset after.
#
show_checklist_variables ()
{
	local checklist=$*
	local var pval
	local log_file=${LOG_OUTPUT_FILE:-${LOG_PATH}/trash.log}
	local _line=${BASH_LINENO[0]}
	local _function=${FUNCNAME[1]}
	local _file=$(basename "${BASH_SOURCE[1]}")

	echo -e "Show variables in function: $_function" "[$_file:$_line]\n" >>$log_file

	for var in $checklist;do
		eval pval=\$$var
		echo -e "\n$var =:" >>$log_file
		if [ $(echo "$pval" | awk -F"/" '{print NF}') -ge 4 ];then
			printf "%s\n" $pval >>$log_file
		else
			printf "%-30s %-30s %-30s %-30s\n" $pval >>$log_file
		fi
	done
}


install_docker() {

	[[ $install_docker != yes ]] && return

	display_alert "Installing" "docker" "info"
	chroot "${SDCARD}" /bin/bash -c "apt-get install -y -qq apt-transport-https ca-certificates curl gnupg2 software-properties-common >/dev/null 2>&1"

	case ${RELEASE} in
		buster|bullseye|bookworm)
		distributor_id="debian"
		;;
		bionic|focal|jammy)
		distributor_id="ubuntu"
		;;
	esac

	if [[ ${BUILD_OS_TYPE} == desktop ]]; then
		mirror_url=https://repo.huaweicloud.com
	else
		mirror_url=https://mirrors.aliyun.com
	fi

	chroot "${SDCARD}" /bin/bash -c "curl -fsSL ${mirror_url}/docker-ce/linux/${distributor_id}/gpg | apt-key add -"
	echo "deb [arch=${ARCH}] ${mirror_url}/docker-ce/linux/${distributor_id} ${RELEASE} stable" > "${SDCARD}"/etc/apt/sources.list.d/docker.list

	chroot "${SDCARD}" /bin/bash -c "apt-get update"
	chroot "${SDCARD}" /bin/bash -c "apt-get install -y -qq docker-ce docker-ce-cli containerd.io"
	chroot "${SDCARD}" /bin/bash -c "sudo groupadd docker"
	chroot "${SDCARD}" /bin/bash -c "sudo usermod -aG docker ${USERNAME}"
	chroot "${SDCARD}" /bin/bash -c "systemctl --no-reload disable docker.service"
}
