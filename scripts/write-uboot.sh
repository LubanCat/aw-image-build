#!/bin/bash
#

source env.txt 2> /dev/null

loop=$1
display_alert "Writing U-boot bootloader" "$loop" "info"
TEMP_DIR=$(mktemp -d || exit 1)
chmod 700 ${TEMP_DIR}

dpkg -x "${DEB_DIR}/u-boot/${UBOOT_DEB}_${REVISION}_${ARCH}.deb" ${TEMP_DIR}/

# source platform install to read $DIR
source ${TEMP_DIR}/usr/lib/u-boot/platform_install.sh
write_uboot_platform "${TEMP_DIR}${DIR}" "$loop"
[[ $? -ne 0 ]] && exit_with_error "U-boot bootloader failed to install" "@host"
rm -rf ${TEMP_DIR}




