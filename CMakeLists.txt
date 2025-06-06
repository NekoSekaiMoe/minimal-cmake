# Copyright (C) 2024-2025 ChenPi11 and dpkg123
# This file is part of the MLinux.
#
# MLinux is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published
# by the Free Software Foundation; either version 2 of the License,
# or (at your option) any later version.

cmake_minimum_required(VERSION 3.15)
project(MLinux VERSION 0.1 LANGUAGES C)

find_program(CCACHE_FOUND ccache)
if(CCACHE_FOUND)
    set_property(GLOBAL PROPERTY RULE_LAUNCH_COMPILE ccache)
    set_property(GLOBAL PROPERTY RULE_LAUNCH_LINK ccache)
    message(STATUS "Using ccache: ${CCACHE_FOUND}")
else()
    message(STATUS "Ccache not found. Compiling with cache will be disabled.")
endif(CCACHE_FOUND)

include(CMakeParseArguments)

# Find required programs
find_program(CC gcc REQUIRED)
find_program(CHMOD chmod REQUIRED)
find_program(CP cp REQUIRED)
find_program(CPIO cpio REQUIRED)
find_program(FDISK fdisk REQUIRED)
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

# Version configurations
set(BUSYBOX_VERSION "1.36.1" CACHE STRING "BusyBox version")
set(LINUX_VERSION "6.7.9" CACHE STRING "Linux kernel version")
string(REGEX REPLACE "([0-9]+)\\.[0-9]+\\.[0-9]+" "\\1" LINUX_VERSION_MAJOR ${LINUX_VERSION})
set(UCLIBC_VERSION "0.9.33.2" CACHE STRING "µClibc version")

# Mirror options with defaults
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

# Architecture and configuration
set(ARCH "x86_64" CACHE STRING "Target architecture")
set(IMAGE_SIZE "6.1M" CACHE STRING "Disk image size")

# Derived variables
set(PWD ${CMAKE_CURRENT_SOURCE_DIR})
set(BUSYBOX "busybox-${BUSYBOX_VERSION}")
set(LINUX "linux-${LINUX_VERSION}")
set(UCLIBC "uClibc-${UCLIBC_VERSION}")
set(KERNEL_IMAGE "${LINUX}/arch/${ARCH}/boot/bzImage")
set(UCLIBC_SYSROOT "${CMAKE_CURRENT_BINARY_DIR}/uclibc")

# Configure mirrors and get URLs
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/mirrors.cmake.in
    ${CMAKE_CURRENT_BINARY_DIR}/mirrors.cmake
    @ONLY
)
include(${CMAKE_CURRENT_BINARY_DIR}/mirrors.cmake)

# Configure uClibc specs
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/uclibc.specs.in
    ${CMAKE_CURRENT_BINARY_DIR}/uclibc.specs
    @ONLY
)

# Define basic file and directory paths
set(BUSYBOX_CONFIG "busybox.${ARCH}.config")
set(FS_DIR "fs")
set(IMAGE_FILE "disk.img")
set(INITRD_FILE "initrd.cpio")
set(KERNEL "vmlinuz")
set(LINUX_CONFIG "linux.${ARCH}.config")
set(ROOTFS "rootfs")
set(SYSLINUX_CFG "syslinux.config")

# Custom commands and targets
add_custom_command(
    OUTPUT ${UCLIBC}.tar.xz
    COMMAND ${WGET} "${UCLIBC_URL}" -q -O ${UCLIBC}.tar.xz
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_custom_command(
    OUTPUT ${UCLIBC}
    COMMAND ${TAR} -xf ${UCLIBC}.tar.xz
    DEPENDS ${UCLIBC}.tar.xz
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_custom_target(uclibc
    COMMAND ${CMAKE_COMMAND} -E make_directory uclibc
    COMMAND ${CP} ${UCLIBC_CONFIG} "${UCLIBC}/.config"
    COMMAND cd ${LINUX} && CC=false ${CMAKE_MAKE_PROGRAM} ARCH=${ARCH} "INSTALL_HDR_PATH=${PWD}/uclibc" headers_install
    COMMAND ${SED} -i "s|@KERNEL_HEADERS@|${PWD}/uclibc/include|g" "${UCLIBC}/.config"
    COMMAND cd ${UCLIBC} && ${CMAKE_MAKE_PROGRAM} all
    COMMAND cd ${UCLIBC} && ${CMAKE_MAKE_PROGRAM} install PREFIX="${PWD}/uclibc"
    DEPENDS ${UCLIBC} ${LINUX}
)

add_custom_command(
    OUTPUT ${BUSYBOX}.tar.bz2
    COMMAND ${WGET} "${BUSYBOX_URL}" -q -O ${BUSYBOX}.tar.bz2
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_custom_target(busybox
    COMMAND ${TAR} -xf ${BUSYBOX}.tar.bz2
    COMMAND ${CP} -f bb-patches/init.c "${BUSYBOX}/init/init.c"
    COMMAND ${PATCH} -p1 "${BUSYBOX}/shell/hush.c" < bb-patches/hush.c.patch
    COMMAND ${PATCH} -p1 "${BUSYBOX}/shell/match.c" < bb-patches/match.c.patch
    COMMAND ${CP} ${BUSYBOX_CONFIG} "${BUSYBOX}/.config"
    COMMAND cd ${BUSYBOX} && ${CMAKE_MAKE_PROGRAM} all CC="${UCLIBC_CC}"
    DEPENDS ${BUSYBOX}.tar.bz2 uclibc
)

add_custom_command(
    OUTPUT ${LINUX}.tar.xz
    COMMAND ${WGET} "${LINUX_URL}" -q -O ${LINUX}.tar.xz
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_custom_target(kernel
    COMMAND ${TAR} -xf ${LINUX}.tar.xz
    COMMAND ${CP} ${LINUX_CONFIG} "${LINUX}/.config"
    COMMAND cd ${LINUX} && ${CMAKE_MAKE_PROGRAM} all CC="${UCLIBC_CC}"
    COMMAND ${CP} ${KERNEL_IMAGE} ${KERNEL}
    COMMAND ${CHMOD} +x ${KERNEL}
    COMMAND ${XZ} -z -c -9 ${KERNEL} > ${KERNEL}.xz
    DEPENDS ${LINUX}.tar.xz initrd
)

add_custom_target(disk_image
    COMMAND ${QEMU_IMG} create -f raw ${IMAGE_FILE} ${IMAGE_SIZE}
    COMMAND ${MKFS} ${IMAGE_FILE}
    COMMAND ${CMAKE_COMMAND} -E make_directory ${FS_DIR}
    COMMAND ${SUDO} ${MOUNT} ${IMAGE_FILE} ${FS_DIR}
    COMMAND ${SUDO} ${CP} -f ${KERNEL} "${FS_DIR}/${KERNEL}"
    COMMAND ${SUDO} ${CP} -f ${SYSLINUX_CFG} "${FS_DIR}/syslinux.cfg"
    COMMAND ${SUDO} ${UMOUNT} ${FS_DIR}
    COMMAND ${SYSLINUX} --install ${IMAGE_FILE}
    COMMAND ${XZ} -z -c -9 ${IMAGE_FILE} > ${IMAGE_FILE}.xz
    DEPENDS kernel
)

# Create rootfs directory and install busybox
add_custom_command(
    OUTPUT ${ROOTFS}
    COMMAND ${CMAKE_COMMAND} -E make_directory ${ROOTFS}
    COMMAND cd ${BUSYBOX} && ${CMAKE_MAKE_PROGRAM} install CONFIG_PREFIX="${CMAKE_BINARY_DIR}/${ROOTFS}" CC="${UCLIBC_CC}"
    COMMAND cd ${ROOTFS} && ${CMAKE_COMMAND} -E make_directory dev
    DEPENDS busybox
)

# Create initrd file
add_custom_command(
    OUTPUT ${INITRD_FILE}
    COMMAND cd ${ROOTFS} && ${FIND} . | ${CPIO} -H newc -o -v --owner root:root > "${CMAKE_BINARY_DIR}/${INITRD_FILE}"
    DEPENDS ${ROOTFS}
)

# Create rootfs.tar
add_custom_command(
    OUTPUT ${ROOTFS}.tar
    COMMAND ${TAR} -c -v -f ${ROOTFS}.tar ${ROOTFS}
    DEPENDS ${ROOTFS}
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

# Create rootfs.tar.xz
add_custom_command(
    OUTPUT ${ROOTFS}.tar.xz
    COMMAND ${XZ} -z -c -9 ${ROOTFS}.tar > ${ROOTFS}.tar.xz
    DEPENDS ${ROOTFS}.tar
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

# Add phony targets for convenience
add_custom_target(rootfs_target ALL DEPENDS ${ROOTFS})
add_custom_target(initrd_target ALL DEPENDS ${INITRD_FILE})
add_custom_target(rootfs_archive ALL DEPENDS ${ROOTFS}.tar.xz)

# Main target
add_custom_target(build_all ALL
    DEPENDS ${ROOTFS}.tar.xz ${KERNEL}.xz ${IMAGE_FILE}.xz
)

# Clean targets
add_custom_target(distclean
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${UCLIBC}
    COMMAND ${CMAKE_COMMAND} -E remove_directory uclibc
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${BUSYBOX}
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${LINUX}
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${ROOTFS}
    COMMAND ${CMAKE_COMMAND} -E remove -f ${ROOTFS}.tar
    COMMAND ${CMAKE_COMMAND} -E remove -f ${ROOTFS}.tar.xz
    COMMAND ${CMAKE_COMMAND} -E remove -f ${INITRD_FILE}
    COMMAND ${CMAKE_COMMAND} -E remove -f ${KERNEL}
    COMMAND ${CMAKE_COMMAND} -E remove -f ${KERNEL}.xz
    COMMAND ${CMAKE_COMMAND} -E remove -f ${IMAGE_FILE}
    COMMAND ${CMAKE_COMMAND} -E remove -f ${IMAGE_FILE}.xz
)

add_custom_target(totally-clean
    COMMAND ${CMAKE_COMMAND} -E remove -f ${UCLIBC_SPECS}
    COMMAND ${CMAKE_COMMAND} -E remove -f ${BUSYBOX}.tar.bz2
    COMMAND ${CMAKE_COMMAND} -E remove -f ${LINUX}.tar.xz
    DEPENDS clean
)

# Check target
add_custom_target(check
    COMMAND ${CMAKE_COMMAND} -E echo "BUSYBOX: ${BUSYBOX}"
    COMMAND ${SUDO} ${DU} -sh ${ROOTFS}.tar.xz ${IMAGE_FILE}.xz
    COMMAND cd ${BUSYBOX} && ${CMAKE_MAKE_PROGRAM} check
    DEPENDS all
)
