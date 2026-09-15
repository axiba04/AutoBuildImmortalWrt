# Reproduce the openwrt-25.12 ImageBuilder FormatPackages implementation:
# https://github.com/immortalwrt/immortalwrt/blob/openwrt-25.12/target/imagebuilder/files/Makefile
GetABISuffix = $(if $(filter libgcc,$(1)),1)

define FormatPackages
$(strip $(foreach pkg,$(strip $(subst ",,$(1))),
  $(eval pkg_name:=$(firstword $(subst =, ,$(pkg))))
  $(if $(findstring =,$(pkg)),$(eval pkg_ver:==$(lastword $(subst =, ,$(pkg)))))
  $(pkg_name)$(call GetABISuffix,$(pkg_name))$(pkg_ver)
))
endef

# Match the failing run: explicit versions precede the default system packages.
$(info $(call FormatPackages,curl nikki=2026.04.08-r1 luci-app-nikki=1.26.1-r1 mihomo-meta=1.19.27 apk-openssl libgcc firewall4 "libc=1.2.5-r5" kernel=6.12.94-r1))
# A second invocation must not inherit the previous invocation final version.
$(info $(call FormatPackages,libgcc curl mihomo-meta=1.19.27))
all: ;
