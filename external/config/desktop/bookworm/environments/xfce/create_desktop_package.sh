# install lightdm greeter
cp -R "${EXTER}"/packages/blobs/desktop/lightdm "${destination}"/etc/lbc

# install default desktop settings
mkdir -p "${destination}"/etc/skel
cp -R "${EXTER}"/packages/blobs/desktop/skel/. "${destination}"/etc/skel

# install wallpapers
mkdir -p "${destination}"/usr/share/backgrounds/
cp "${EXTER}"/packages/blobs/desktop/desktop-wallpapers/*.png "${destination}"/usr/share/backgrounds

# install logo for login screen
mkdir -p "${destination}"/usr/share/pixmaps/lbc
cp "${EXTER}"/packages/blobs/desktop/icons/lubancat.png "${destination}"/usr/share/pixmaps/lbc
