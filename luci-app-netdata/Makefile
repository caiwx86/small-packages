# SPDX-License-Identifier: GPL-3.0
#
# Copyright (C) 2022-2025 muink <https://github.com/muink>
# Copyright (C) 2025 caiwx86 <https://github.com/caiwx86>
#
# This is free software, licensed under the GNU General Public License v3.

include $(TOPDIR)/rules.mk

LUCI_NAME:=luci-app-netdata

LUCI_TITLE:=LuCI Netdata
# netdata-ssl is preferred (native HTTPS). The conditional dependencies keep
# this app visible and buildable in a stock tree even when the custom
# netdata-ssl package is not present. Select exactly one backend in menuconfig.
LUCI_DEPENDS:=+openssl-util +netdata-ssl

LUCI_DESCRIPTION:=Real-time performance monitoring with optional native HTTPS

PKG_NAME:=luci-app-netdata
PKG_VERSION:=1.0
PKG_RELEASE:=2

PKG_MAINTAINER:=Anya Lin <hukk1996@gmail.com>
PKG_LICENSE:=GPL-3.0

include $(TOPDIR)/feeds/luci/luci.mk

# --- DO NOT REMOVE -------------------------------------------------------
# OpenWrt 的 include/scan.mk 用下面的命令发现 package/ 下的软件包：
#   find -L package -name Makefile | xargs grep 'call (Build/DefaultTargets|BuildPackage|KernelPackage)'
# LuCI 插件本身不调用 BuildPackage（由 luci.mk 完成），只能靠下面这行字面量
# 被扫描器识别。删掉它，本包会被静默漏扫：make defconfig 会丢掉
# CONFIG_PACKAGE_luci-app-netdata=y，固件里没有该插件，而且不会报错。
# call BuildPackage - OpenWrt buildroot signature
