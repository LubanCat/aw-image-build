# 使用 Ubuntu 20.04 作为基础镜像
FROM ubuntu:20.04

# 禁用交互模式并更新包列表，安装必要的软件包
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update &&  \
    apt-get install -y \
    sudo git vim psmisc uuid uuid-runtime busybox   \
    acl aptly aria2 bc binfmt-support bison btrfs-progs build-essential       \
    ca-certificates ccache cpio cryptsetup curl debian-archive-keyring        \
    debian-keyring debootstrap device-tree-compiler zlib1g-dev swig zip       \
    dialog dirmngr dosfstools dwarves f2fs-tools fakeroot flex gawk           \
    gcc-arm-linux-gnueabihf gdisk gpg imagemagick jq kmod libbison-dev        \
    libc6-dev-armhf-cross libelf-dev libfdt-dev libfile-fcntllock-perl        \
    libfl-dev liblz4-tool libncurses-dev libpython2.7-dev libssl-dev          \
    libusb-1.0-0-dev linux-base locales lzop ncurses-base ncurses-term        \
    nfs-kernel-server ntpdate p7zip-full parted patchutils pigz pixz          \
    pkg-config pv python3-dev python3-distutils qemu-user-static rsync        \
    systemd-container u-boot-tools udev unzip uuid-dev wget whiptail          \
    && rm -rf /var/lib/apt/lists/*

# 设置 root 用户的密码为 "root"
RUN echo "root:root" | chpasswd

# 创建 dev 用户并将其添加到 sudoers 列表中，设置密码为 "ubuntu"
RUN useradd -m dev && echo "dev:ubuntu" | chpasswd && usermod -aG sudo dev

# 切换到 dev 用户
USER dev

# 指定默认工作目录（可选）
WORKDIR /home/dev

# 使用 dev 用户执行 bash shell
CMD ["/bin/bash"]
