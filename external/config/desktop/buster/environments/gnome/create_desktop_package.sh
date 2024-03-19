# install default desktop settings
mkdir -p "${destination}"/etc/skel
cp -R "${EXTER}"/packages/blobs/desktop/skel/. "${destination}"/etc/skel

# install logo for login screen
mkdir -p "${destination}"/usr/share/pixmaps/lbc
cp "${EXTER}"/packages/blobs/desktop/icons/lubancat.png "${destination}"/usr/share/pixmaps/lbc

# install wallpapers
mkdir -p "${destination}"/usr/share/backgrounds/gnome/
cp "${EXTER}"/packages/blobs/desktop/wallpapers/lbc*.jpg "${destination}"/usr/share/backgrounds/gnome/
mkdir -p "${destination}"/usr/share/gnome-background-properties
cat <<-EOF > "${destination}"/usr/share/gnome-background-properties/lbc.xml
<?xml version="1.0"?>
<!DOCTYPE wallpapers SYSTEM "gnome-wp-list.dtd">
<wallpapers>
  <wallpaper deleted="false">
    <name>LubanCat light</name>
    <filename>/usr/share/backgrounds/gnome/lbc/18-Dre0x-Minum-light-3840x2160.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>LubanCat dark</name>
    <filename>/usr/share/backgrounds/gnome/lbc/03-Dre0x-Minum-dark-3840x2160.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
</wallpapers>
EOF
