cmake_minimum_required(VERSION 3.14)
project(MLinux C)

# ==============================
# 1. 用户可配置选项（替代 AC_ARG_WITH）
# ==============================

# 版本
set(BUSYBOX_VERSION "1.36.1" CACHE STRING "BusyBox version")
set(LINUX_VERSION "6.7.9" CACHE STRING "Linux kernel version")
set(UCLIBC_VERSION "0.9.33.2" CACHE STRING "uClibc version")

# 镜像（支持 OFFICIAL/CDN/TSINGHUA/ALIYUN/USTC/自定义URL）
set(LINUX_MIRROR "OFFICIAL" CACHE STRING "Linux mirror: OFFICIAL|CDN|TSINGHUA|ALIYUN|USTC|<URL>")
set(BUSYBOX_MIRROR "OFFICIAL" CACHE STRING "BusyBox mirror: OFFICIAL|<URL>")
set(UCLIBC_MIRROR "OFFICIAL" CACHE STRING "uClibc mirror: OFFICIAL|<URL>")

# 架构
set(ARCH "x86_64" CACHE STRING "Target architecture")

# ==============================
# 2. 查找必要工具（替代 AC_PATH_PROG）
# ==============================

find_program(CHMOD chmod REQUIRED)
find_program(CP cp REQUIRED)
find_program(CPIO cpio REQUIRED)
find_program(FIND find REQUIRED)
find_program(MKDIR mkdir REQUIRED)
find_program(MKFS mkfs.fat REQUIRED)
find_program(MOUNT mount REQUIRED)
find_program(PATCH patch REQUIRED)
find_program(QEMU_IMG qemu-img REQUIRED)
find_program(RM rm REQUIRED)
find_program(SED sed REQUIRED)
find_program(SUDO sudo REQUIRED)
find_program(SYSLINUX syslinux REQUIRED)
find_program(TAR tar REQUIRED)
find_program(UMOUNT umount REQUIRED)
find_program(WGET wget REQUIRED)
find_program(XZ xz REQUIRED)
find_program(DU du REQUIRED)

# ==============================
# 3. 衍生变量
# ==============================

string(REGEX REPLACE "\\..*" "" LINUX_VERSION_MAJOR "${LINUX_VERSION}")
set(UCLIBC_SYSROOT "${CMAKE_CURRENT_BINARY_DIR}/uclibc")

# ==============================
# 4. 生成配置文件
# ==============================

# 生成 uclibc.specs
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/uclibc.specs.in
    ${CMAKE_CURRENT_BINARY_DIR}/uclibc.specs
    @ONLY
)

# 生成 mirrors.cmake（用于内部逻辑）
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/mirrors.cmake.in
    ${CMAKE_CURRENT_BINARY_DIR}/mirrors.cmake
    @ONLY
)

# 加载镜像变量
include(${CMAKE_CURRENT_BINARY_DIR}/mirrors.cmake)

# ==============================
# 5. 路径定义
# ==============================

set(BUSYBOX_SRC_DIR "${CMAKE_CURRENT_BINARY_DIR}/busybox-${BUSYBOX_VERSION}")
set(LINUX_SRC_DIR "${CMAKE_CURRENT_BINARY_DIR}/linux-${LINUX_VERSION}")
set(UCLIBC_SRC_DIR "${CMAKE_CURRENT_BINARY_DIR}/uClibc-${UCLIBC_VERSION}")
set(ROOTFS_DIR "${CMAKE_CURRENT_BINARY_DIR}/rootfs")
set(INITRD_FILE "${CMAKE_CURRENT_BINARY_DIR}/initrd.cpio")
set(KERNEL_FILE "${CMAKE_CURRENT_BINARY_DIR}/vmlinuz")
set(IMAGE_FILE "${CMAKE_CURRENT_BINARY_DIR}/disk.img")

# ==============================
# 6. 构建步骤（自定义命令）
# ==============================

# --- 下载并解压 uClibc ---
add_custom_command(
    OUTPUT ${UCLIBC_SRC_DIR}/.extracted
    COMMAND ${WGET} "${UCLIBC_URL}" -O ${UCLIBC_SRC_DIR}.tar.xz
    COMMAND ${TAR} -xf ${UCLIBC_SRC_DIR}.tar.xz
    COMMAND ${CMAKE_COMMAND} -E touch ${UCLIBC_SRC_DIR}/.extracted
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    DEPENDS ${WGET} ${TAR}
    COMMENT "Downloading and extracting uClibc"
)

# --- 下载并解压 BusyBox ---
add_custom_command(
    OUTPUT ${BUSYBOX_SRC_DIR}/.extracted
    COMMAND ${WGET} "${BUSYBOX_URL}" -O ${BUSYBOX_SRC_DIR}.tar.bz2
    COMMAND ${TAR} -xf ${BUSYBOX_SRC_DIR}.tar.bz2
    COMMAND ${CMAKE_COMMAND} -E touch ${BUSYBOX_SRC_DIR}/.extracted
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    DEPENDS ${WGET} ${TAR}
    COMMENT "Downloading and extracting BusyBox"
)

# --- 打补丁 ---
add_custom_command(
    OUTPUT ${BUSYBOX_SRC_DIR}/.patched
    COMMAND ${CP} ${CMAKE_CURRENT_SOURCE_DIR}/bb-patches/init.c ${BUSYBOX_SRC_DIR}/init/init.c
    COMMAND ${PATCH} -p1 < ${CMAKE_CURRENT_SOURCE_DIR}/bb-patches/hush.c.patch
    COMMAND ${PATCH} -p1 < ${CMAKE_CURRENT_SOURCE_DIR}/bb-patches/match.c.patch
    COMMAND ${CMAKE_COMMAND} -E touch ${BUSYBOX_SRC_DIR}/.patched
    WORKING_DIRECTORY ${BUSYBOX_SRC_DIR}
    DEPENDS ${BUSYBOX_SRC_DIR}/.extracted ${PATCH} ${CP}
)

# --- 下载并解压 Linux ---
add_custom_command(
    OUTPUT ${LINUX_SRC_DIR}/.extracted
    COMMAND ${WGET} "${LINUX_URL}" -O ${LINUX_SRC_DIR}.tar.xz
    COMMAND ${TAR} -xf ${LINUX_SRC_DIR}.tar.xz
    COMMAND ${CMAKE_COMMAND} -E touch ${LINUX_SRC_DIR}/.extracted
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    DEPENDS ${WGET} ${TAR}
    COMMENT "Downloading and extracting Linux kernel"
)

# --- 构建 uClibc ---
add_custom_command(
    OUTPUT ${UCLIBC_SYSROOT}/lib/libc.a
    COMMAND ${MKDIR} -p ${UCLIBC_SYSROOT}
    COMMAND ${CP} ${CMAKE_CURRENT_SOURCE_DIR}/uclibc.${ARCH}.config ${UCLIBC_SRC_DIR}/.config
    COMMAND ${SED} -i "s|@KERNEL_HEADERS@|${UCLIBC_SYSROOT}/include|g" ${UCLIBC_SRC_DIR}/.config
    COMMAND cd ${LINUX_SRC_DIR} && CC=false make ARCH=${ARCH} INSTALL_HDR_PATH=${UCLIBC_SYSROOT} headers_install
    COMMAND cd ${UCLIBC_SRC_DIR} && make -j$(nproc) all
    COMMAND cd ${UCLIBC_SRC_DIR} && make install PREFIX=${UCLIBC_SYSROOT}
    DEPENDS ${UCLIBC_SRC_DIR}/.extracted ${LINUX_SRC_DIR}/.extracted
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    COMMENT "Building uClibc"
)

# --- 构建 BusyBox ---
add_custom_command(
    OUTPUT ${BUSYBOX_SRC_DIR}/busybox
    COMMAND ${CP} ${CMAKE_CURRENT_SOURCE_DIR}/busybox.${ARCH}.config ${BUSYBOX_SRC_DIR}/.config
    COMMAND cd ${BUSYBOX_SRC_DIR} && make -j$(nproc) all CC="${CMAKE_C_COMPILER} -specs ${CMAKE_CURRENT_BINARY_DIR}/uclibc.specs -fno-stack-protector"
    DEPENDS ${BUSYBOX_SRC_DIR}/.patched ${UCLIBC_SYSROOT}/lib/libc.a
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    COMMENT "Building BusyBox"
)

# --- 安装到 rootfs ---
add_custom_command(
    OUTPUT ${ROOTFS_DIR}/bin/busybox
    COMMAND ${MKDIR} -p ${ROOTFS_DIR}
    COMMAND cd ${BUSYBOX_SRC_DIR} && make install CONFIG_PREFIX=${ROOTFS_DIR} CC="${CMAKE_C_COMPILER} -specs ${CMAKE_CURRENT_BINARY_DIR}/uclibc.specs -fno-stack-protector"
    COMMAND ${MKDIR} -p ${ROOTFS_DIR}/dev
    DEPENDS ${BUSYBOX_SRC_DIR}/busybox
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    COMMENT "Installing BusyBox to rootfs"
)

# --- 生成 initrd ---
add_custom_command(
    OUTPUT ${INITRD_FILE}
    COMMAND cd ${ROOTFS_DIR} && ${FIND} . | ${CPIO} -H newc -o -v --owner root:root > ${INITRD_FILE}
    DEPENDS ${ROOTFS_DIR}/bin/busybox
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    COMMENT "Creating initrd"
)

# --- 构建 Linux 内核 ---
add_custom_command(
    OUTPUT ${KERNEL_FILE}
    COMMAND ${CP} ${CMAKE_CURRENT_SOURCE_DIR}/linux.${ARCH}.config ${LINUX_SRC_DIR}/.config
    COMMAND cd ${LINUX_SRC_DIR} && make -j$(nproc) all CC="${CMAKE_C_COMPILER} -specs ${CMAKE_CURRENT_BINARY_DIR}/uclibc.specs -fno-stack-protector"
    COMMAND ${CP} ${LINUX_SRC_DIR}/arch/${ARCH}/boot/bzImage ${KERNEL_FILE}
    COMMAND ${CHMOD} +x ${KERNEL_FILE}
    DEPENDS ${LINUX_SRC_DIR}/.extracted ${INITRD_FILE}
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    COMMENT "Building Linux kernel"
)

# --- 生成可启动镜像 ---
add_custom_command(
    OUTPUT ${IMAGE_FILE}
    COMMAND ${QEMU_IMG} create -f raw ${IMAGE_FILE} 6.1M
    COMMAND ${MKFS} ${IMAGE_FILE}
    COMMAND ${MKDIR} -p ${CMAKE_CURRENT_BINARY_DIR}/fs
    COMMAND ${SUDO} ${MOUNT} ${IMAGE_FILE} ${CMAKE_CURRENT_BINARY_DIR}/fs
    COMMAND ${SUDO} ${CP} ${KERNEL_FILE} ${CMAKE_CURRENT_BINARY_DIR}/fs/vmlinuz
    COMMAND ${SUDO} ${CP} ${CMAKE_CURRENT_SOURCE_DIR}/syslinux.config ${CMAKE_CURRENT_BINARY_DIR}/fs/syslinux.cfg
    COMMAND ${SUDO} ${UMOUNT} ${CMAKE_CURRENT_BINARY_DIR}/fs || true
    COMMAND ${SYSLINUX} --install ${IMAGE_FILE}
    DEPENDS ${KERNEL_FILE} ${SYSLINUX}
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    COMMENT "Creating bootable disk image"
)

# ==============================
# 7. 最终目标
# ==============================

add_custom_target(all
    DEPENDS
        ${ROOTFS_DIR}/bin/busybox
        ${KERNEL_FILE}
        ${IMAGE_FILE}
)

# 压缩产物（可选）
add_custom_command(
    OUTPUT ${ROOTFS_DIR}.tar.xz
    COMMAND ${TAR} -c -f ${ROOTFS_DIR}.tar -C ${CMAKE_CURRENT_BINARY_DIR} rootfs
    COMMAND ${XZ} -z -c -9 ${ROOTFS_DIR}.tar > ${ROOTFS_DIR}.tar.xz
    DEPENDS ${ROOTFS_DIR}/bin/busybox
)

add_custom_command(
    OUTPUT ${IMAGE_FILE}.xz
    COMMAND ${XZ} -z -c -9 ${IMAGE_FILE} > ${IMAGE_FILE}.xz
    DEPENDS ${IMAGE_FILE}
)

add_custom_target(compressed
    DEPENDS ${ROOTFS_DIR}.tar.xz ${IMAGE_FILE}.xz
)

# ==============================
# 8. 清理目标
# ==============================

add_custom_target(clean
    COMMAND ${RM} -rf
        ${UCLIBC_SRC_DIR}
        uclibc
        ${BUSYBOX_SRC_DIR}
        ${LINUX_SRC_DIR}
        ${ROOTFS_DIR}
        ${ROOTFS_DIR}.tar
        ${ROOTFS_DIR}.tar.xz
        ${INITRD_FILE}
        ${KERNEL_FILE}
        ${KERNEL_FILE}.xz
        ${IMAGE_FILE}
        ${IMAGE_FILE}.xz
        fs
    COMMENT "Cleaning build artifacts"
)

# ==============================
# 9. 检查目标（类似原 check）
# ==============================

add_custom_target(check
    DEPENDS all
    COMMAND echo "BUSYBOX: busybox-${BUSYBOX_VERSION}"
    COMMAND ${SUDO} ${DU} -sh ${ROOTFS_DIR}.tar.xz ${IMAGE_FILE}.xz
    COMMAND cd ${BUSYBOX_SRC_DIR} && make check
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
)
