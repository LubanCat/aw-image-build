#!/bin/bash
#
# Copyright (c) 2013-2021 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# Functions:

# create_distro_package
# create_desktop_bsp_package
# add_apt_sources


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
