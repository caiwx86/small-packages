# SPDX-License-Identifier: GPL-3.0
#
# Copyright (C) 2022-2025 muink <https://github.com/muink>
# Copyright (C) 2025 caiwx86 <https://github.com/caiwx86>
#
# This is free software, licensed under the GNU General Public License v3.

include $(TOPDIR)/rules.mk

LUCI_NAME:=luci-app-netdata

LUCI_TITLE:=LuCI Netdata
LUCI_DEPENDS:=+netdata-ssl +openssl-util

LUCI_DESCRIPTION:=Real-time performance monitoring with native HTTPS support

PKG_VERSION:=20251117
PKG_RELEASE:=3

PKG_MAINTAINER:=Anya Lin <hukk1996@gmail.com>
PKG_LICENSE:=GPL-3.0

include $(TOPDIR)/feeds/luci/luci.mk
