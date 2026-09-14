#!/bin/bash

# =========================
# 代理：Nikki
# =========================

CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-nikki-zh-cn"


# =========================
# 网络诊断工具
# =========================

CUSTOM_PACKAGES="$CUSTOM_PACKAGES curl wget-ssl tcpdump ip-full bind-dig"


# =========================
# WireGuard，可选
# =========================

CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-proto-wireguard"


# =========================
# 分区扩容，可选
# =========================

CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-app-partexp luci-i18n-partexp-zh-cn"
