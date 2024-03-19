## 项目介绍

本项目是基于armbian镜像构建系统修改的适用于野火LubanCat(鲁班猫)全志系列板卡Debian及Ubuntu镜像构建项目

## 使用方法

#### 交互式构建参数选择

`./build.sh`

#### 命令行指定参数构建

`sudo ./build.sh  BOARD=lubancat-a1 BRANCH=current BUILD_OPT=rootfs RELEASE=bullseye BUILD_OS_TYPE=server`

## 常见问题

-   No such script: /usr/share/debootstrap/scripts/jammy

    debootstrap不是最新版本，可以手动安装最新版。
    ```
    wget http://ftp.cn.debian.org/debian/pool/main/d/debootstrap/debootstrap_1.0.134_all.deb
    sudo dpkg -i debootstrap_1.0.134_all.deb
    ```

-   Release signed by unknown key (key id 605C66F00D6C9793)
    The specified keyring /usr/share/keyrings/debian-archive-keyring.gpg may be incorrect or out of date

    gpg秘钥过期，debian-archive-keyring不是最新版本，可以手动安装最新版。
    ```
    wget http://ftp.cn.debian.org/debian/pool/main/d/debian-archive-keyring/debian-archive-keyring_2023.4_all.deb
    sudo dpkg -i debian-archive-keyring_2023.4_all.deb
    ```
