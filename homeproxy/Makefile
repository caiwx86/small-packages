# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2022-2023 ImmortalWrt.org

include $(TOPDIR)/rules.mk

LUCI_TITLE:=The modern ImmortalWrt proxy platform for ARM64/AMD64
LUCI_PKGARCH:=all
LUCI_DEPENDS:= \
	+sing-box \
	+firewall4 \
	+kmod-nft-tproxy \
	+curl \
	+jsonfilter \
	+ucode-mod-digest

PKG_NAME:=luci-app-homeproxy
PKG_VERSION=$(PKG_SRC_VERSION)
PKG_RELEASE:=7
PKG_PO_VERSION=$(PKG_SRC_VERSION)-r$(PKG_RELEASE)

define Package/luci-app-homeproxy/conffiles
/etc/config/homeproxy
/etc/homeproxy/cache/
/etc/homeproxy/certs/
/etc/homeproxy/ruleset/
/etc/homeproxy/resources/direct_list.txt
/etc/homeproxy/resources/proxy_list.txt
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
