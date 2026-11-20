# SPDX-License-Identifier: GPL-3.0
#
# Copyright (C) 2022-2025 muink <https://github.com/muink>
# Copyright (C) 2025 caiwx86 <https://github.com/caiwx86>
#
# This is free software, licensed under the GNU General Public License v3.

include $(TOPDIR)/rules.mk

# luci.mk derives PKG_NAME from LUCI_NAME (PKG_NAME?=$(LUCI_NAME)) and uses
# LUCI_NAME to derive LUCI_TYPE (app), LUCI_BASENAME (netdata) and the i18n
# package names. Keep LUCI_NAME; PKG_NAME is repeated explicitly so the binary
# package name stays stable even if the checkout directory is renamed.
LUCI_NAME:=luci-app-netdata
PKG_NAME:=luci-app-netdata

LUCI_TITLE:=LuCI Netdata
# netdata-ssl is preferred (native HTTPS). The conditional dependencies keep
# this app visible and buildable in a stock tree even when the custom
# netdata-ssl package is not present. Select exactly one backend in menuconfig.
LUCI_DEPENDS:=+luci-base +openssl-util +PACKAGE_netdata-ssl:netdata-ssl +PACKAGE_netdata:netdata
LUCI_MAINTAINER:=Anya Lin <hukk1996@gmail.com>
LUCI_URL:=https://github.com/caiwx86/luci-app-netdata

LUCI_DESCRIPTION:=Real-time performance monitoring with optional native HTTPS

PKG_VERSION:=20251117
PKG_RELEASE:=5

PKG_MAINTAINER:=Anya Lin <hukk1996@gmail.com>
PKG_LICENSE:=GPL-3.0

include $(TOPDIR)/feeds/luci/luci.mk
