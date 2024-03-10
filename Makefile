#
# Copyright (C) 2024 cnfatal@gmal.com
#
# This is free software, licensed under the GNU General Public License v2.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=ddns-scripts-alidns
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0
PKG_MAINTAINER:=cnfatal <cnfatal@gmail.com>

include $(INCLUDE_DIR)/package.mk

define Package/ddns-scripts-alidns
	SECTION:=net
	CATEGORY:=Network
	SUBMENU:=IP Addresses and Names
	PKGARCH:=all
	TITLE:=Dynamic DNS scripts extension for aliyun DNS
	DEPENDS:=ddns-scripts +curl +openssl-util
endef

define Package/ddns-scripts-alidns/description
	Dynamic DNS Client scripts extension for aliyun DNS.
	Version: $(PKG_VERSION)-$(PKG_RELEASE)
	Info   : https://github.com/cnfatal/ddns-scripts-alidns
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/ddns-scripts-alidns/install
	$(INSTALL_DIR) $(1)/usr/lib/ddns
	$(INSTALL_BIN) ./files/usr/lib/ddns/update_aliyun.com.sh $(1)/usr/lib/ddns/

	$(INSTALL_DIR) $(1)/usr/share/ddns/default
	$(INSTALL_DATA) ./files/usr/share/ddns/default/aliyun.com.json $(1)/usr/share/ddns/default/
endef

define Package/ddns-scripts-alidns/prerm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	/etc/init.d/ddns stop
fi
exit 0
endef

$(eval $(call BuildPackage,ddns-scripts-alidns))