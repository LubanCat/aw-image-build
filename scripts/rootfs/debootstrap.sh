#!/bin/bash
#

# 导入环境变量
source env.txt 2> /dev/null

# debootstrap第一步安装
display_alert "Installing base system" "Stage 1/2" "info"

cd $SDCARD

echo debootstrap --variant=minbase --include=${Debootstrap_Packages// /,} ${PACKAGE_LIST_EXCLUDE:+ --exclude=${PACKAGE_LIST_EXCLUDE// /,}} --arch=$ARCH --components=${Debootstrap_Components} $Debootstrap_Option --foreign $RELEASE $SDCARD/ http://$APT_MIRROR;
eval 'debootstrap --variant=minbase --include=${Debootstrap_Packages// /,} ${PACKAGE_LIST_EXCLUDE:+ --exclude=${PACKAGE_LIST_EXCLUDE// /,}} \
	--arch=$ARCH --components=${Debootstrap_Components} $Debootstrap_Option --foreign $RELEASE $SDCARD/ http://$APT_MIRROR'

cp -v /usr/bin/$QEMU_BINARY $SDCARD/usr/bin/

mkdir -p $SDCARD/usr/share/keyrings/
cp -v /usr/share/keyrings/*-archive-keyring.gpg $SDCARD/usr/share/keyrings/

# debootstrap 第二步安装
display_alert "Installing base system" "Stage 2/2" "info"

eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -e -c "/debootstrap/debootstrap --second-stage"'

mount_chroot "$SDCARD"

display_alert "Diverting" "initctl/start-stop-daemon" "info"
# policy-rc.d script prevents starting or reloading services during image creation
printf '#!/bin/sh\nexit 101' > $SDCARD/usr/sbin/policy-rc.d
LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "dpkg-divert --quiet --local --rename --add /sbin/initctl" &> /dev/null
LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "dpkg-divert --quiet --local --rename --add /sbin/start-stop-daemon" &> /dev/null
printf '#!/bin/sh\necho "Warning: Fake start-stop-daemon called, doing nothing"' > $SDCARD/sbin/start-stop-daemon
printf '#!/bin/sh\necho "Warning: Fake initctl called, doing nothing"' > $SDCARD/sbin/initctl
chmod 755 $SDCARD/usr/sbin/policy-rc.d
chmod 755 $SDCARD/sbin/initctl
chmod 755 $SDCARD/sbin/start-stop-daemon

# 配置语言环境
display_alert "Configuring locales" "$DEST_LANG" "info"

[[ -f $SDCARD/etc/locale.gen ]] && sed -i "s/^# $DEST_LANG/$DEST_LANG/" $SDCARD/etc/locale.gen
eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "locale-gen $DEST_LANG"'
eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "update-locale LANG=$DEST_LANG LANGUAGE=$DEST_LANG LC_MESSAGES=$DEST_LANG"'

if [[ -f $SDCARD/etc/default/console-setup ]]; then
	sed -e 's/CHARMAP=.*/CHARMAP="UTF-8"/' -e 's/FONTSIZE=.*/FONTSIZE="8x16"/' \
		-e 's/CODESET=.*/CODESET="guess"/' -i $SDCARD/etc/default/console-setup
	eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "setupcon --save --force"'
fi

# stage: create apt-get sources list
create_sources_list "$RELEASE" "$SDCARD/"

# add armhf arhitecture to arm64
# [[ $ARCH == arm64 ]] && eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "dpkg --add-architecture armhf"'

# this should fix resolvconf installation failure in some cases
chroot $SDCARD /bin/bash -c 'echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections'

# stage: update packages list
display_alert "Update $RELEASE package list" "apt-get -q -y update" "info"
eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -e -c "apt-get -q -y update"'

# stage: upgrade base packages from xxx-updates and xxx-backports repository branches
display_alert "Upgrade $RELEASE base packages" "apt-get upgrade" "info"
eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -e -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q upgrade"'

# stage: install additional packages
display_alert "Install $RELEASE main packages" "apt-get install $PACKAGE_MAIN_LIST" "info"
eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -e -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q \
	--no-install-recommends install $PACKAGE_MAIN_LIST"'

if [[ $BUILD_OS_TYPE == "desktop" ]]; then
	# FIXME Myy : Are we keeping this only for Desktop users,
	# or should we extend this to CLI users too ?
	# There might be some clunky boards that require Debian packages from
	# specific repos...
	display_alert "Adding apt sources for Desktop packages"
	add_apt_sources

	ls -l "${SDCARD}/usr/share/keyrings"
	ls -l "${SDCARD}/etc/apt/sources.list.d"
	cat "${SDCARD}/etc/apt/sources.list"

	apt_desktop_install_flags=""
	if [[ ! -z ${DESKTOP_APT_FLAGS_SELECTED+x} ]]; then
		for flag in ${DESKTOP_APT_FLAGS_SELECTED}; do
			apt_desktop_install_flags+=" --install-${flag}"
		done
	else
		# Myy : Using the previous default option, if the variable isn't defined
		# And ONLY if it's not defined !
		apt_desktop_install_flags+=" --no-install-recommends"
	fi

	display_alert "Install $RELEASE desktop packages" "apt-get install ${apt_desktop_install_flags} $PACKAGE_LIST_DESKTOP" "info"
	eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -e -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q \
		install ${apt_desktop_install_flags} $PACKAGE_LIST_DESKTOP"'
fi

# Remove packages from packages.uninstall
display_alert "Uninstall $RELEASE packages" "apt-get purge $PACKAGE_LIST_UNINSTALL" "info"
eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -e -c "DEBIAN_FRONTEND=noninteractive apt-get -y -qq \
	purge $PACKAGE_LIST_UNINSTALL"'

# stage: purge residual packages
display_alert "Uninstall $RELEASE residual packages" "apt-get remove --purge $PURGINGPACKAGES" "info"
PURGINGPACKAGES=$(chroot $SDCARD /bin/bash -c "dpkg -l | grep \"^rc\" | awk '{print \$2}' | tr \"\n\" \" \"")
eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -e -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q \
	remove --purge $PURGINGPACKAGES"'

# stage: remove downloaded packages
chroot $SDCARD /bin/bash -c "apt-get -y autoremove; apt-get clean"

# print space
df -h

packages_hash=$(get_package_list_hash $ROOTFSCACHE_VERSION)

cache_type="server"
[[ -n ${DESKTOP_ENVIRONMENT} ]] && cache_type="${DESKTOP_ENVIRONMENT}"

cache_name=${RELEASE}-${cache_type}-${ARCH}.$packages_hash.tar.gz
cache_file=${BUILD_DIR}/rootfs-base/${cache_name}
# create list of installed packages for debug purposes
chroot $SDCARD /bin/bash -c "dpkg --get-selections" | grep -v deinstall | awk '{print $1}' | cut -f1 -d':' > ${cache_file}.list 2>&1

# creating xapian index that synaptic runs faster
if [[ $BUILD_OS_TYPE == desktop ]]; then
	display_alert "Recreating Synaptic search index" "Please wait" "info"
	chroot $SDCARD /bin/bash -c "[[ -f /usr/sbin/update-apt-xapian-index ]] && /usr/sbin/update-apt-xapian-index -u"
fi

# this is needed for the build process later since resolvconf generated file in /run is not saved
echo "nameserver 8.8.8.8" > $SDCARD/etc/resolv.conf

# stage: make rootfs cache archive
display_alert "Ending debootstrap process" "$RELEASE" "info"
sync
# the only reason to unmount here is compression progress display
# based on rootfs size calculation
umount_chroot "$SDCARD"

tar cp --xattrs --directory=$SDCARD/ --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
	--exclude='./sys/*' --exclude='./home/*' --exclude='./root/*' . | pv -p -b -r -s $(du -sb $SDCARD/ | cut -f1) -N "$cache_name" | pigz > $cache_file
