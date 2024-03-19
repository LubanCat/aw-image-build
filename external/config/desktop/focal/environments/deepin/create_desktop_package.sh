# install lightdm greeter
cp -R "${EXTER}"/packages/blobs/desktop/lightdm "${destination}"/etc/lbc

# install default desktop settings
mkdir -p "${destination}"/etc/skel
cp -R "${EXTER}"/packages/blobs/desktop/skel/. "${destination}"/etc/skel

# install wallpapers
mkdir -p "${destination}"/usr/share/backgrounds/
cp "${EXTER}"/packages/blobs/desktop/desktop-wallpapers/*.jpg "${destination}"/usr/share/backgrounds

# install logo for login screen
mkdir -p "${destination}"/usr/share/pixmaps/lbc
cp "${EXTER}"/packages/blobs/desktop/icons/lubancat.png "${destination}"/usr/share/pixmaps/lbc

#generate wallpaper list for background changer
mkdir -p "${destination}"/usr/sharedeepin-background-properties
cat <<EOF > "${destination}"/usr/share/deepin-background-properties/lbc.xml
<?xml version="1.0"?>
<!DOCTYPE wallpapers SYSTEM "deepin-wp-list.dtd">
<wallpapers>
  <wallpaper deleted="false">
    <name>LubanCat black-pyscho</name>
    <filename>/usr/share/backgrounds/lbc-4k-black-psycho.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>LubanCat bluie-circle</name>
    <filename>/usr/share/backgrounds/lbc-4k-blue-circle.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>LubanCat blue-monday</name>
    <filename>/usr/share/backgrounds/lbc-4k-blue-monday.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>LubanCat blue-penguin</name>
    <filename>/usr/share/backgrounds/lbc-4k-blue-penguin.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>LubanCat gray-resultado</name>
    <filename>/usr/share/backgrounds/lbc-4k-gray.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>LubanCat green-penguin</name>
    <filename>/usr/share/backgrounds/lbc-4k-green-penguin.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>LubanCat green-retro</name>
    <filename>/usr/share/backgrounds/lbc-4k-green-retro.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>LubanCat green-wall-penguin</name>
    <filename>/usr/share/backgrounds/lbc-4k-green-wall-penguin.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>LubanCat 4k-neglated</name>
    <filename>/usr/share/backgrounds/lbc-4k-neglated.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>LubanCat neon-gray-penguin</name>
    <filename>/usr/share/backgrounds/lbc-4k-neon-gray-penguin.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>LubanCat plastic-love</name>
    <filename>/usr/share/backgrounds/lbc-4k-plastic-love.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>LubanCat purple-penguine</name>
    <filename>/usr/share/backgrounds/lbc-4k-purple-penguine.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
    <wallpaper deleted="false">
    <name>LubanCat purplepunk-resultado</name>
    <filename>/usr/share/backgrounds/lbc-4k-purplepunk.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>LubanCat red-penguin-dark</name>
    <filename>/usr/share/backgrounds/lbc-4k-red-penguin-dark.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>LubanCat red-penguin</name>
    <filename>/usr/share/backgrounds/lbc-4k-red-penguin.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>LubanCat light</name>
    <filename>/usr/share/backgrounds/lbc/18-Dre0x-Minum-light-3840x2160.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>LubanCat dark</name>
    <filename>/usr/share/backgrounds/lbc/03-Dre0x-Minum-dark-3840x2160.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>LubanCat uc</name>
    <filename>/usr/share/backgrounds/lbc-full-under-construction-3840-2160.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>LubanCat clear</name>
    <filename>/usr/share/backgrounds/LubanCat-clear-rounded-bakcground-3840-2160.jpg</filename>
    <options>zoom</options>
    <pcolor>#ffffff</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
</wallpapers>
EOF
