# Copyright (C) 2024-2025 ChenPi11 and dpkg123
# This file is part of the MLinux.
#
# MLinux is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published
# by the Free Software Foundation; either version 2 of the License,
# or (at your option) any later version.

cmake_minimum_required(VERSION 3.15)
project(MLinux VERSION 0.1 LANGUAGES C)

# Find ccache early
find_program(CCACHE_PROGRAM ccache)
if(CCACHE_PROGRAM)
    # Configure ccache
    set(CMAKE_C_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
    set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
    message(STATUS "Using ccache: ${CCACHE_PROGRAM}")
    
    # Set environment variable for sub-make processes
    set(ENV{CCACHE_DIR} "${CMAKE_BINARY_DIR}/.ccache")
    set(ENV{CCACHE_COMPRESS} "1")
else()
    message(STATUS "Ccache not found. Compiling without cache.")
endif()

# Set compiler wrapper
if(CCACHE_PROGRAM)
    set(COMPILER_WRAPPER "${CCACHE_PROGRAM}")
else()
    set(COMPILER_WRAPPER "")
endif()

# Set CC command with ccache
set(CC_COMMAND "${COMPILER_WRAPPER} ${CMAKE_C_COMPILER}")

# Add ccache stats target
add_custom_target(ccache_stats
    COMMAND ${CCACHE_PROGRAM} -s
    COMMENT "Showing ccache statistics"
)

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
set(LINUX "linux-${LINUX_VERSION}")
set(KERNEL_IMAGE "${LINUX}/arch/${ARCH}/boot/bzImage")

# Set compiler flags
set(CC_FLAGS "-fno-stack-protector")
set(UCLIBC_SPECS "${CMAKE_BINARY_DIR}/uclibc.specs")

# Function to check file exists
function(ensure_file file)
    if(NOT EXISTS "${file}")
        message(FATAL_ERROR "Required file not found: ${file}")
    endif()
endfunction()

# Validate required files
ensure_file("${CMAKE_SOURCE_DIR}/${LINUX_CONFIG}")

# Derived variables
set(PWD ${CMAKE_CURRENT_SOURCE_DIR})
set(BUSYBOX "busybox-${BUSYBOX_VERSION}")
set(LINUX "linux-${LINUX_VERSION}")
set(UCLIBC "uClibc-${UCLIBC_VERSION}")
set(KERNEL_IMAGE "${LINUX}/arch/${ARCH}/boot/bzImage")
set(UCLIBC_SYSROOT "${CMAKE_CURRENT_BINARY_DIR}/uclibc")
set(BUSYBOX_CONFIG "busybox.${ARCH}.config")
set(FS_DIR "fs")
set(IMAGE_FILE "disk.img")
set(INITRD_FILE "initrd.cpio")
set(KERNEL "vmlinuz")
set(LINUX_CONFIG "linux.${ARCH}.config")
set(ROOTFS "rootfs")
set(SYSLINUX_CFG "syslinux.config")
set(UCLIBC_CONFIG "uclibc.${ARCH}.config")

# Set UCLIBC_CC before use
set(UCLIBC_CC "${CC_COMMAD} -specs \"${CMAKE_BINARY_DIR}/uclibc.specs\" -fno-stack-protector")

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

# Linux kernel source preparation
add_custom_command(
    OUTPUT ${LINUX}
    COMMAND ${TAR} -xf ${LINUX}.tar.xz
    DEPENDS ${LINUX}.tar.xz
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_custom_command(
    OUTPUT ${LINUX}.tar.xz
    COMMAND ${WGET} "${LINUX_URL}" -q -O ${LINUX}.tar.xz
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

# uClibc preparation and build
add_custom_command(
    OUTPUT ${UCLIBC}
    COMMAND ${TAR} -xf ${UCLIBC}.tar.xz
    DEPENDS ${UCLIBC}.tar.xz
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_custom_command(
    OUTPUT ${UCLIBC}.tar.xz
    COMMAND ${WGET} "${UCLIBC_URL}" -q -O ${UCLIBC}.tar.xz
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

# uClibc preparation and build
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/uclibc
    COMMAND ${CMAKE_COMMAND} -E make_directory uclibc
    # Fix: Added destination path for config file copy
    COMMAND ${SED} -i "'s|114514|${CMAKE_BINARY_DIR}/uclibc/include|g'" "${CMAKE_SOURCE_DIR}/${UCLIBC_CONFIG}"
    COMMAND ${CP} -f ${CMAKE_SOURCE_DIR}/${UCLIBC_CONFIG} "${UCLIBC}/.config"
    # Fix: Changed ninja to make since we're building uClibc
    COMMAND cd ${CMAKE_BINARY_DIR}/${LINUX} && CC=false make ARCH=${ARCH} "INSTALL_HDR_PATH=${CMAKE_BINARY_DIR}/uclibc" headers_install
    COMMAND cd ${CMAKE_BINARY_DIR}/${UCLIBC} && make all >log.txt 2>&1
    COMMAND cd ${CMAKE_BINARY_DIR}/${UCLIBC} && make install PREFIX="${CMAKE_BINARY_DIR}/uclibc" >log.txt 2>&1
    DEPENDS ${UCLIBC} ${LINUX}
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Building uClibc"
)

# BusyBox preparation and build
add_custom_command(
    OUTPUT ${BUSYBOX}.tar.bz2
    COMMAND ${WGET} "${BUSYBOX_URL}" -q -O ${BUSYBOX}.tar.bz2
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

# BusyBox preparation and build
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/${BUSYBOX}
    # Extract BusyBox
    COMMAND ${TAR} -xf ${BUSYBOX}.tar.bz2
    
    # Apply patches and config
    COMMAND ${CMAKE_COMMAND} -E copy_if_different 
        "${CMAKE_SOURCE_DIR}/bb-patches/init.c" 
        "${CMAKE_BINARY_DIR}/${BUSYBOX}/init/init.c"
    
    COMMAND ${PATCH} -p1 -i "${CMAKE_SOURCE_DIR}/bb-patches/hush.c.patch"
        "${CMAKE_BINARY_DIR}/${BUSYBOX}/shell/hush.c"
    
    COMMAND ${PATCH} -p1 -i "${CMAKE_SOURCE_DIR}/bb-patches/match.c.patch"
        "${CMAKE_BINARY_DIR}/${BUSYBOX}/shell/match.c"
    
    COMMAND ${CMAKE_COMMAND} -E copy_if_different 
        "${CMAKE_SOURCE_DIR}/${BUSYBOX_CONFIG}" 
        "${CMAKE_BINARY_DIR}/${BUSYBOX}/.config"
    
    # Build BusyBox (using properly escaped CC)
    COMMAND ${CMAKE_COMMAND} -E env 
        "CC=${CC_COMMAD} -specs '${CMAKE_BINARY_DIR}/uclibc.specs' -fno-stack-protector"
        make -C "${CMAKE_BINARY_DIR}/${BUSYBOX}" all > "${CMAKE_BINARY_DIR}/busybox_build.log" 2>&1
    
    DEPENDS 
        ${CMAKE_BINARY_DIR}/${BUSYBOX}.tar.bz2
        ${CMAKE_SOURCE_DIR}/bb-patches/init.c
        ${CMAKE_SOURCE_DIR}/bb-patches/hush.c.patch
        ${CMAKE_SOURCE_DIR}/bb-patches/match.c.patch
        ${CMAKE_SOURCE_DIR}/${BUSYBOX_CONFIG}
        ${CMAKE_BINARY_DIR}/uclibc.specs
    
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Building BusyBox"
)

# Create rootfs directory and install busybox
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/${ROOTFS}
    # Create rootfs directory
    COMMAND ${CMAKE_COMMAND} -E make_directory ${ROOTFS}
    
    # Install busybox with proper CC environment
    COMMAND ${CMAKE_COMMAND} -E env 
        "CC=${CC_COMMAD} -specs ${CMAKE_BINARY_DIR}/uclibc.specs -fno-stack-protector"
        make -C "${CMAKE_BINARY_DIR}/${BUSYBOX}" 
        install 
        "CONFIG_PREFIX=${CMAKE_BINARY_DIR}/${ROOTFS}"
        > "${CMAKE_BINARY_DIR}/rootfs_install.log" 2>&1
    
    # Create necessary directories
    COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_BINARY_DIR}/${ROOTFS}/dev"
    
    DEPENDS
        ${CMAKE_BINARY_DIR}/${BUSYBOX}
        ${CMAKE_BINARY_DIR}/uclibc.specs
    
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Creating root filesystem"
)

# Alternative approach using a shell script
configure_file(
    "${CMAKE_SOURCE_DIR}/scripts/build_kernel.sh.in"
    "${CMAKE_BINARY_DIR}/build_kernel.sh"
    @ONLY
)

add_custom_command(
    OUTPUT ${INITRD_FILE}
    COMMAND cd ${ROOTFS} && ${FIND} . | ${CPIO} -H newc -o -v --owner root:root > "${CMAKE_BINARY_DIR}/${INITRD_FILE}"
    DEPENDS ${ROOTFS}
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

# Kernel build command using shell script
add_custom_command(
    OUTPUT 
        ${CMAKE_BINARY_DIR}/vmlinuz 
        ${CMAKE_BINARY_DIR}/vmlinuz.xz
    
    # Copy kernel config
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_SOURCE_DIR}/${LINUX_CONFIG}"
        "${CMAKE_BINARY_DIR}/${LINUX}/.config"
    
    # Run build script
    COMMAND bash "${CMAKE_BINARY_DIR}/build_kernel.sh"
    
    DEPENDS
        ${CMAKE_BINARY_DIR}/${LINUX}
        ${CMAKE_SOURCE_DIR}/${LINUX_CONFIG}
        ${CMAKE_BINARY_DIR}/uclibc.specs
        ${CMAKE_BINARY_DIR}/${INITRD_FILE}
        ${CMAKE_BINARY_DIR}/build_kernel.sh
    
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Building Linux kernel"
)

# Set environment variables at the top of CMakeLists.txt
set(KERNEL_CC "${CC_COMMAD} -specs ${CMAKE_BINARY_DIR}/uclibc.specs -fno-stack-protector")

# Add validation target for kernel build
add_custom_target(validate_kernel
    COMMAND ${CMAKE_COMMAND} -E echo "Validating kernel build..."
    COMMAND test -f "${CMAKE_BINARY_DIR}/vmlinuz" || (echo "vmlinuz not found" && exit 1)
    COMMAND test -x "${CMAKE_BINARY_DIR}/vmlinuz" || (echo "vmlinuz not executable" && exit 1)
    COMMAND test -f "${CMAKE_BINARY_DIR}/vmlinuz.xz" || (echo "vmlinuz.xz not found" && exit 1)
    DEPENDS ${CMAKE_BINARY_DIR}/vmlinuz ${CMAKE_BINARY_DIR}/vmlinuz.xz
)

# Disk image creation
add_custom_command(
    OUTPUT ${IMAGE_FILE} ${IMAGE_FILE}.xz
    COMMAND ${QEMU_IMG} create -f raw ${IMAGE_FILE} ${IMAGE_SIZE}
    COMMAND ${MKFS} ${IMAGE_FILE}
    COMMAND ${CMAKE_COMMAND} -E make_directory ${FS_DIR}
    COMMAND ${SUDO} ${MOUNT} ${IMAGE_FILE} ${FS_DIR}
    COMMAND ${SUDO} ${CP} -f ${KERNEL} "${FS_DIR}/${KERNEL}"
    COMMAND ${SUDO} ${CP} -f ${CMAKE_SOURCE_DIR}/${SYSLINUX_CFG} "${FS_DIR}/syslinux.cfg"
    COMMAND ${SUDO} ${UMOUNT} ${FS_DIR}
    COMMAND ${SYSLINUX} --install ${IMAGE_FILE}
    COMMAND ${XZ} -z -c -9 ${IMAGE_FILE} > ${IMAGE_FILE}.xz
    DEPENDS ${KERNEL}.xz
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

# Create rootfs archive
add_custom_command(
    OUTPUT ${ROOTFS}.tar
    COMMAND ${TAR} -cf ${ROOTFS}.tar ${ROOTFS}
    DEPENDS ${ROOTFS}
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

add_custom_command(
    OUTPUT ${ROOTFS}.tar.xz
    COMMAND ${XZ} -z -c -9 ${ROOTFS}.tar > ${ROOTFS}.tar.xz
    DEPENDS ${ROOTFS}.tar
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

# Main build target
add_custom_target(build_all ALL
    DEPENDS ${ROOTFS}.tar.xz ${KERNEL}.xz ${IMAGE_FILE}.xz
)

# Clean targets
add_custom_target(distclean
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_BINARY_DIR}/${UCLIBC}
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_BINARY_DIR}/uclibc
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_BINARY_DIR}/${BUSYBOX}
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_BINARY_DIR}/${LINUX}
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_BINARY_DIR}/${ROOTFS}
    COMMAND ${CMAKE_COMMAND} -E remove -f ${CMAKE_BINARY_DIR}/${ROOTFS}.tar
    COMMAND ${CMAKE_COMMAND} -E remove -f ${CMAKE_BINARY_DIR}/${ROOTFS}.tar.xz
    COMMAND ${CMAKE_COMMAND} -E remove -f ${CMAKE_BINARY_DIR}/${INITRD_FILE}
    COMMAND ${CMAKE_COMMAND} -E remove -f ${CMAKE_BINARY_DIR}/${KERNEL}
    COMMAND ${CMAKE_COMMAND} -E remove -f ${CMAKE_BINARY_DIR}/${KERNEL}.xz
    COMMAND ${CMAKE_COMMAND} -E remove -f ${CMAKE_BINARY_DIR}/${IMAGE_FILE}
    COMMAND ${CMAKE_COMMAND} -E remove -f ${CMAKE_BINARY_DIR}/${IMAGE_FILE}.xz
)

add_custom_target(totally-clean
    COMMAND ${CMAKE_COMMAND} -E remove -f ${CMAKE_BINARY_DIR}/uclibc.specs
    COMMAND ${CMAKE_COMMAND} -E remove -f ${CMAKE_BINARY_DIR}/${BUSYBOX}.tar.bz2
    COMMAND ${CMAKE_COMMAND} -E remove -f ${CMAKE_BINARY_DIR}/${LINUX}.tar.xz
    DEPENDS distclean
)

# Check target
add_custom_target(check
    COMMAND ${CMAKE_COMMAND} -E echo "BUSYBOX: ${BUSYBOX}"
    COMMAND ${SUDO} ${DU} -sh ${ROOTFS}.tar.xz ${IMAGE_FILE}.xz
    COMMAND cd ${BUSYBOX} && make check
    DEPENDS build_all
)
