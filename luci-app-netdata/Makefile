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

PKG_MAINTAINER:=Anya Lin <hukk1996@gmail.com>
PKG_LICENSE:=GPL-3.0

include $(TOPDIR)/feeds/luci/luci.mk
