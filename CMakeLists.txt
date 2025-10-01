# Copyright (C) 2025 ChenPi11
# This file is part of the MLinux.
#
# MLinux is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published
# by the Free Software Foundation; either version 2 of the License,
# or (at your option) any later version.

cmake_minimum_required(VERSION 3.15)
project(MLinux VERSION 0.1 LANGUAGES C)

# ==============================
# ccache support (recommended way)
# ==============================
find_program(CCACHE_PROGRAM ccache)
if(CCACHE_PROGRAM)
    set(CMAKE_C_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
    message(STATUS "Using ccache: ${CCACHE_PROGRAM}")
    set(ENV{CCACHE_DIR} "${CMAKE_BINARY_DIR}/.ccache")
    set(ENV{CCACHE_COMPRESS} "1")
else()
    message(STATUS "ccache not found. Compiling without cache.")
endif()

# ==============================
# Find required tools
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
find_program(SUDO sudo REQUIRED)
find_program(SYSLINUX syslinux REQUIRED)
find_program(TAR tar REQUIRED)
find_program(UMOUNT umount REQUIRED)
find_program(WGET wget REQUIRED)
find_program(XZ xz REQUIRED)
find_program(DU du REQUIRED)

# ==============================
# User-configurable options
# ==============================
set(BUSYBOX_VERSION "1.36.1" CACHE STRING "BusyBox version")
set(LINUX_VERSION "6.7.9" CACHE STRING "Linux kernel version")
set(UCLIBC_VERSION "0.9.33.2" CACHE STRING "µClibc version")

string(REGEX REPLACE "^([0-9]+)\\.[0-9]+\\.[0-9]+$" "\\1" LINUX_VERSION_MAJOR "${LINUX_VERSION}")

set(ARCH "x86_64" CACHE STRING "Target architecture")
set(IMAGE_SIZE "6.1M" CACHE STRING "Disk image size")

# Mirror options
set(MIRROR_OPTIONS "OFFICIAL;CDN;TSINGHUA;ALIYUN;USTC;CUSTOME")
set(LINUX_MIRROR "OFFICIAL" CACHE STRING "Linux kernel mirror")
set_property(CACHE LINUX_MIRROR PROPERTY STRINGS ${MIRROR_OPTIONS})
set(LINUX_MIRROR_CUSTOME "" CACHE STRING "Custom Linux mirror URL")

set(BUSYBOX_MIRROR "OFFICIAL" CACHE STRING "BusyBox mirror")
set_property(CACHE BUSYBOX_MIRROR PROPERTY STRINGS "OFFICIAL;CUSTOME")
set(BUSYBOX_MIRROR_CUSTOME "" CACHE STRING "Custom BusyBox mirror URL")

set(UCLIBC_MIRROR "OFFICIAL" CACHE STRING "µClibc mirror")
set_property(CACHE UCLIBC_MIRROR PROPERTY STRINGS "OFFICIAL;CUSTOME")
set(UCLIBC_MIRROR_CUSTOME "" CACHE STRING "Custom µClibc mirror URL")

# ==============================
# Paths and filenames
# ==============================
set(BUSYBOX "busybox-${BUSYBOX_VERSION}")
set(LINUX "linux-${LINUX_VERSION}")
set(UCLIBC "uClibc-${UCLIBC_VERSION}")

set(BUSYBOX_CONFIG "busybox.${ARCH}.config")
set(LINUX_CONFIG "linux.${ARCH}.config")
set(UCLIBC_CONFIG "uclibc.${ARCH}.config.in")

set(ROOTFS "${CMAKE_BINARY_DIR}/rootfs")
set(INITRD_FILE "${CMAKE_BINARY_DIR}/initrd.cpio")
set(KERNEL_FILE "${CMAKE_BINARY_DIR}/vmlinuz")
set(IMAGE_FILE "${CMAKE_BINARY_DIR}/disk.img")
set(FS_DIR "${CMAKE_BINARY_DIR}/fs")
set(SYSLINUX_CFG "syslinux.config")

set(UCLIBC_SYSROOT "${CMAKE_BINARY_DIR}/uclibc")
set(UCLIBC_SPECS "${CMAKE_BINARY_DIR}/uclibc.specs")

# ==============================
# Validate required config files
# ==============================
function(ensure_file file)
    if(NOT EXISTS "${file}")
        message(FATAL_ERROR "Required config file not found: ${file}")
    endif()
endfunction()

ensure_file("${CMAKE_SOURCE_DIR}/${BUSYBOX_CONFIG}")
ensure_file("${CMAKE_SOURCE_DIR}/${LINUX_CONFIG}")
ensure_file("${CMAKE_SOURCE_DIR}/${UCLIBC_CONFIG}")
ensure_file("${CMAKE_SOURCE_DIR}/${SYSLINUX_CFG}")
ensure_file("${CMAKE_SOURCE_DIR}/bb-patches/init.c")
ensure_file("${CMAKE_SOURCE_DIR}/bb-patches/hush.c.patch")
ensure_file("${CMAKE_SOURCE_DIR}/bb-patches/match.c.patch")

# ==============================
# Generate config files
# ==============================
configure_file(
    ${CMAKE_SOURCE_DIR}/mirrors.cmake.in
    ${CMAKE_BINARY_DIR}/mirrors.cmake
    @ONLY
)
include(${CMAKE_BINARY_DIR}/mirrors.cmake)

configure_file(
    ${CMAKE_SOURCE_DIR}/uclibc.specs.in
    ${CMAKE_BINARY_DIR}/uclibc.specs
    @ONLY
)

# ==============================
# Download & Extract
# ==============================
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/${LINUX}.tar.xz
    COMMAND ${WGET} "${LINUX_URL}" -q -O ${LINUX}.tar.xz
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Downloading Linux kernel"
)

add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/${LINUX}
    COMMAND ${TAR} -xf ${LINUX}.tar.xz
    DEPENDS ${LINUX}.tar.xz
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Extraxting Linux kernel"
)

add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/${UCLIBC}.tar.xz
    COMMAND ${WGET} "${UCLIBC_URL}" -q -O ${UCLIBC}.tar.xz
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Downloading uClibc"
)

add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/${UCLIBC}
    COMMAND ${TAR} -xf ${UCLIBC}.tar.xz
    DEPENDS ${UCLIBC}.tar.xz
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Extracting uClibc"
)

add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/${BUSYBOX}.tar.bz2
    COMMAND ${WGET} "${BUSYBOX_URL}" -q -O ${BUSYBOX}.tar.bz2
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Downloading BusyBox"
)

add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/${BUSYBOX}
    COMMAND ${TAR} -xf ${BUSYBOX}.tar.bz2
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${CMAKE_SOURCE_DIR}/bb-patches/init.c
        ${CMAKE_BINARY_DIR}/${BUSYBOX}/init/init.c
    COMMAND cd ${CMAKE_BINARY_DIR}/${BUSYBOX}/shell && ${PATCH} -p0 < ${CMAKE_SOURCE_DIR}/bb-patches/hush.c.patch
    COMMAND cd ${CMAKE_BINARY_DIR}/${BUSYBOX}/shell && ${PATCH} -p0 < ${CMAKE_SOURCE_DIR}/bb-patches/match.c.patch
    DEPENDS ${BUSYBOX}.tar.bz2
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Patching Busybox"
)

# ==============================
# Build uClibc
# ==============================
set(KERNEL_HEADERS "${UCLIBC_SYSROOT}/include")
configure_file(
    ${CMAKE_SOURCE_DIR}/uclibc.${ARCH}.config.in
    ${CMAKE_BINARY_DIR}/${UCLIBC}/.config
    @ONLY
)

# 然后在 uClibc 构建命令中直接使用这个 .config
add_custom_command(
    OUTPUT ${UCLIBC_SYSROOT}/lib/libc.a
    COMMAND ${MKDIR} -p ${UCLIBC_SYSROOT}
    COMMAND cd ${CMAKE_BINARY_DIR}/${LINUX} && CC=false make ARCH=${ARCH} "INSTALL_HDR_PATH=${UCLIBC_SYSROOT}" headers_install
    COMMAND cd ${CMAKE_BINARY_DIR}/${UCLIBC} && make -j${CMAKE_BUILD_PARALLEL_LEVEL} all
    COMMAND cd ${CMAKE_BINARY_DIR}/${UCLIBC} && make install PREFIX=${UCLIBC_SYSROOT}
    DEPENDS ${UCLIBC} ${LINUX} ${CMAKE_BINARY_DIR}/${UCLIBC}/.config
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Building uClibc"
)

# ==============================
# Build BusyBox
# ==============================
set(BUSYBOX_CC "${CMAKE_C_COMPILER} -specs ${UCLIBC_SPECS} -fno-stack-protector")

add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/${BUSYBOX}/busybox
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${CMAKE_SOURCE_DIR}/${BUSYBOX_CONFIG}
        ${CMAKE_BINARY_DIR}/${BUSYBOX}/.config
    COMMAND ${CMAKE_COMMAND} -E env "CC=${BUSYBOX_CC}"
        make -C ${BUSYBOX} -j${CMAKE_BUILD_PARALLEL_LEVEL} all
    DEPENDS ${BUSYBOX} ${UCLIBC_SYSROOT}/lib/libc.a
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Building BusyBox"
)

# ==============================
# Create rootfs
# ==============================
add_custom_command(
    OUTPUT ${ROOTFS}/bin/busybox
    COMMAND ${MKDIR} -p ${ROOTFS}
    COMMAND ${CMAKE_COMMAND} -E env "CC=${BUSYBOX_CC}"
        make -C ${BUSYBOX} install "CONFIG_PREFIX=${ROOTFS}"
    COMMAND ${MKDIR} -p ${ROOTFS}/dev
    DEPENDS ${BUSYBOX}/busybox
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Creating rootfs"
)

# ==============================
# Create initrd
# ==============================
add_custom_command(
    OUTPUT ${INITRD_FILE}
    COMMAND cd ${ROOTFS} && ${FIND} . | ${CPIO} -H newc -o -v --owner root:root > ${INITRD_FILE}
    DEPENDS ${ROOTFS}/bin/busybox
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

# ==============================
# Build Linux kernel
# ==============================
set(KERNEL_CC "${CMAKE_C_COMPILER} -specs ${UCLIBC_SPECS} -fno-stack-protector")

add_custom_command(
    OUTPUT ${KERNEL_FILE}
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${CMAKE_SOURCE_DIR}/${LINUX_CONFIG}
        ${CMAKE_BINARY_DIR}/${LINUX}/.config
    COMMAND ${CMAKE_COMMAND} -E env "CC=${KERNEL_CC}"
        make -C ${LINUX} -j${CMAKE_BUILD_PARALLEL_LEVEL} all
    COMMAND ${CP} ${CMAKE_BINARY_DIR}/${LINUX}/arch/${ARCH}/boot/bzImage ${KERNEL_FILE}
    COMMAND ${CHMOD} +x ${KERNEL_FILE}
    DEPENDS ${LINUX} ${INITRD_FILE}
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Building Linux kernel"
)

# ==============================
# Create bootable image
# ==============================
add_custom_command(
    OUTPUT ${IMAGE_FILE}
    COMMAND ${QEMU_IMG} create -f raw ${IMAGE_FILE} ${IMAGE_SIZE}
    COMMAND ${MKFS} ${IMAGE_FILE}
    COMMAND ${MKDIR} -p ${FS_DIR}
    COMMAND ${SUDO} ${MOUNT} ${IMAGE_FILE} ${FS_DIR}
    COMMAND ${SUDO} ${CP} ${KERNEL_FILE} ${FS_DIR}/vmlinuz
    COMMAND ${SUDO} ${CP} ${CMAKE_SOURCE_DIR}/${SYSLINUX_CFG} ${FS_DIR}/syslinux.cfg
    COMMAND ${SUDO} ${UMOUNT} ${FS_DIR} || true
    COMMAND ${SYSLINUX} --install ${IMAGE_FILE}
    DEPENDS ${KERNEL_FILE}
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Creating bootable disk image"
)

# ==============================
# Compress outputs
# ==============================
add_custom_command(
    OUTPUT ${ROOTFS}.tar.xz
    COMMAND ${TAR} -c -f ${ROOTFS}.tar -C ${CMAKE_BINARY_DIR} rootfs
    COMMAND ${XZ} -z -c -9 ${ROOTFS}.tar > ${ROOTFS}.tar.xz
    DEPENDS ${ROOTFS}/bin/busybox
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_custom_command(
    OUTPUT ${IMAGE_FILE}.xz
    COMMAND ${XZ} -z -c -9 ${IMAGE_FILE} > ${IMAGE_FILE}.xz
    DEPENDS ${IMAGE_FILE}
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

# ==============================
# Targets
# ==============================
add_custom_target(buildall ALL
    DEPENDS ${ROOTFS}.tar.xz ${KERNEL_FILE} ${IMAGE_FILE}.xz
)

add_custom_target(check
    COMMAND ${CMAKE_COMMAND} -E echo "BUSYBOX: ${BUSYBOX}"
    COMMAND ${SUDO} ${DU} -sh ${ROOTFS}.tar.xz ${IMAGE_FILE}.xz
    COMMAND cd ${BUSYBOX} && make check
    DEPENDS all
)

add_custom_target(dryclean
    COMMAND ${RM} -rf
        ${UCLIBC} uclibc ${BUSYBOX} ${LINUX} ${ROOTFS}
        ${ROOTFS}.tar ${ROOTFS}.tar.xz
        ${INITRD_FILE}
        ${KERNEL_FILE} ${KERNEL_FILE}.xz
        ${IMAGE_FILE} ${IMAGE_FILE}.xz
        ${FS_DIR}
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

if(CCACHE_PROGRAM)
    add_custom_target(ccache-stats
        COMMAND ${CCACHE_PROGRAM} -s
        COMMENT "Show ccache statistics"
    )
endif()
