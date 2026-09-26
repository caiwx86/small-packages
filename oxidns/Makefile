include $(TOPDIR)/rules.mk

PKG_NAME:=oxidns
PKG_VERSION:=1.6.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/svenshi/oxidns.git
PKG_SOURCE_DATE:=2026-09-26
PKG_SOURCE_VERSION:=5e83394976790f60bd4ed0f059aa65ea1c279c21
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
PKG_SOURCE:=$(PKG_SOURCE_SUBDIR).tar.zst
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Sven Shi <isvenshi@gmail.com>

PKG_CONFIG_DEPENDS:=CONFIG_PACKAGE_oxidns-webui
PKG_BUILD_DEPENDS:=rust/host PACKAGE_oxidns-webui:node/host
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk

define Package/oxidns
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=DNS
  TITLE:=OxiDNS - High-performance DNS Engine
  DEPENDS:=
  URL:=https://github.com/svenshi/oxidns
endef

define Package/oxidns/description
  A high-performance, programmable DNS engine in Rust with flexible
  pipeline-based routing.
endef

define Package/oxidns-webui
  $(call Package/oxidns/Default)
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=DNS
  TITLE+= webui
  DEPENDS:=+oxidns
endef

define Package/oxidns-webui/description
  A web UI for the OxiDNS server.
endef

define Package/oxidns/conffiles
/etc/oxidns/config.yaml
endef

define Build/Prepare
	$(call Build/Prepare/Default)

ifneq ($(CONFIG_PACKAGE_oxidns-webui),)
	(cd $(PKG_BUILD_DIR)/webui && \
		npx -y pnpm install --ignore-scripts && \
		npx -y pnpm build)
endif
endef

define Build/Compile
	$(call Build/Compile/Cargo,,--features full)
endef

define Package/oxidns/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/target/$(RUSTC_TARGET_ARCH)/release/oxidns $(1)/usr/bin/

	$(INSTALL_DIR) $(1)/etc/oxidns
	$(INSTALL_CONF) ./files/config.yaml $(1)/etc/oxidns/config.yaml
endef

define Package/oxidns-webui/install
	$(INSTALL_DIR) $(1)/usr/share/oxidns
	$(CP) $(PKG_BUILD_DIR)/webui/out $(1)/usr/share/oxidns/webui
endef

$(eval $(call BuildPackage,oxidns))
$(eval $(call BuildPackage,oxidns-webui))