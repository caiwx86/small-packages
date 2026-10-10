include $(TOPDIR)/rules.mk

PKG_NAME:=oxidns
PKG_VERSION:=1.6.1
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/svenshi/oxidns.git
PKG_SOURCE_DATE:=2026-10-10
PKG_SOURCE_VERSION:=f9019c6f823731f7bd090102aa31327dafdecbf4
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
PKG_SOURCE:=$(PKG_SOURCE_SUBDIR).tar.zst
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Sven Shi <isvenshi@gmail.com>

PKG_CONFIG_DEPENDS:=CONFIG_PACKAGE_oxidns-webui

# rust 是编译 oxidns 本体必需；node/npm 只在需要构建 webui 时才依赖
PKG_BUILD_DEPENDS:=rust/host PACKAGE_oxidns-webui:node/host
PKG_BUILD_PARALLEL:=1

WEBUI_DIST:=out

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk

# ---------------------------------------------------------------------------
# Package 定义
# ---------------------------------------------------------------------------

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
  TITLE:=OxiDNS - Web UI
  DEPENDS:=+oxidns
endef

define Package/oxidns-webui/description
  A web UI for the OxiDNS server.
endef

define Package/oxidns/conffiles
/etc/oxidns/config.yaml
endef

# ---------------------------------------------------------------------------
# Prepare：仅做源码解压与补丁
# ---------------------------------------------------------------------------

define Build/Prepare
	$(call Build/Prepare/Default)
endef

# ---------------------------------------------------------------------------
# Configure
# ---------------------------------------------------------------------------

define Build/Configure
	$(call Build/Configure/Default)
endef

# ---------------------------------------------------------------------------
# Compile：先编译 Rust，再构建前端（若选中 webui）
# 用 shell 判断而不是 Makefile 的 ifneq，避免配方在解析期被固定
# ---------------------------------------------------------------------------

define Build/Compile
	$(call Build/Compile/Cargo,,--features full)

	if [ -n "$(CONFIG_PACKAGE_oxidns-webui)" ]; then \
		echo "===> Building OxiDNS webui ..."; \
		cd $(PKG_BUILD_DIR)/webui || { echo "webui dir missing"; exit 1; }; \
		if [ ! -f package.json ]; then \
			echo "ERROR: webui/package.json not found"; exit 1; \
		fi; \
		npx -y pnpm install --ignore-scripts || { echo "pnpm install failed"; exit 1; }; \
		npx -y pnpm build || { echo "pnpm build failed"; exit 1; }; \
		if [ ! -d "$(WEBUI_DIST)" ]; then \
			echo "ERROR: webui build output '$(WEBUI_DIST)' not found"; \
			ls -la; exit 1; \
		fi; \
		echo "===> webui build OK: $(WEBUI_DIST)"; \
	fi
endef

# ---------------------------------------------------------------------------
# Install
# files/seed 由 GitHub Actions 根据 files/config.yaml 的 downloads 列表生成，
# 内含首次启动所需的规则文件（antiad.txt / geosite.dat / geoip.dat 等），
# 目录结构与 downloads 中的 dir 一致，直接按原路径安装
# ---------------------------------------------------------------------------

define Package/oxidns/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/target/$(RUSTC_TARGET_ARCH)/release/oxidns $(1)/usr/bin/

	$(INSTALL_DIR) $(1)/etc/oxidns
	$(INSTALL_CONF) ./files/config.yaml $(1)/etc/oxidns/config.yaml

	if [ -d ./files/seed ]; then \
		$(CP) ./files/seed/. $(1)/; \
	fi
endef

define Package/oxidns-webui/install
	$(INSTALL_DIR) $(1)/usr/share/oxidns/webui
	$(CP) $(PKG_BUILD_DIR)/webui/$(WEBUI_DIST)/. $(1)/usr/share/oxidns/webui/
endef

$(eval $(call BuildPackage,oxidns))
$(eval $(call BuildPackage,oxidns-webui))