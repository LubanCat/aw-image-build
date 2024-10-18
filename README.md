## 项目介绍

本项目是基于armbian镜像构建系统修改的适用于野火LubanCat(鲁班猫)全志系列板卡Debian及Ubuntu镜像构建项目

## 使用方法

#### 交互式构建参数选择

`./build.sh`

#### 命令行指定参数构建

`sudo ./build.sh  BOARD=lubancat-a1 BRANCH=current BUILD_OPT=rootfs RELEASE=bullseye BUILD_OS_TYPE=server`

## Docker 构建

#### 创建Docker镜像

在包含 Dockerfile 的目录下，运行以下命令来构建 Docker 镜像：
```
sudo docker build -t ubuntu-dev .
```
#### 运行容器

挂载aw-image-build目录到容器并运行容器
```
# 在aw-image-build目录下获取当前目录的绝对路径
HOST_DIR=$(pwd)

# 根据获取的路径挂载并运行容器
sudo docker run -it --privileged --name ubuntu-dev -v /dev:/tmp/dev:ro -v ${HOST_DIR}:${HOST_DIR}:rw ubuntu-dev /bin/bash

# 在Docker容器的终端总输入以下命令退出容器
exit

# 查看所有的容器状态
sudo docker ps -a

# 启动停止的容器
sudo docker start ubuntu-dev

# 重新进入已经启动的容器
sudo docker exec -it ubuntu-dev /bin/bash

# 删除已经创建的容器
sudo docker rm ubuntu-dev
```

#### 编译镜像

进入容器/home/dev/Linux/aw-image-build目录后，编译方法与在宿主机编译的方式相同

## 常见问题

-   No such script: /usr/share/debootstrap/scripts/jammy

    debootstrap不是最新版本，可以手动安装最新版。
    ```
    wget http://ftp.cn.debian.org/debian/pool/main/d/debootstrap/debootstrap_1.0.137ubuntu3_all.deb
    sudo dpkg -i debootstrap_1.0.137ubuntu3_all.deb
    ```

-   Release signed by unknown key (key id 605C66F00D6C9793)
    The specified keyring /usr/share/keyrings/debian-archive-keyring.gpg may be incorrect or out of date

    gpg秘钥过期，debian-archive-keyring不是最新版本，可以手动安装最新版。
    ```
    wget http://ftp.cn.debian.org/debian/pool/main/d/debian-archive-keyring/debian-archive-keyring_2023.4_all.deb
    sudo dpkg -i debian-archive-keyring_2023.4_all.deb
    ```
