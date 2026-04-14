include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-daed

LUCI_TITLE:=LuCI Support for DAED
LUCI_DEPENDS:=+daed +zoneinfo-asia +luci-compat
LUCI_PKGARCH:=all

define Package/$(PKG_NAME)/conffiles
endef

include $(TOPDIR)/feeds/luci/luci.mk
# call BuildPackage - OpenWrt buildroot signature
