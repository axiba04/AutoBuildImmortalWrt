#!/bin/bash
# 兼容 25.12 ImageBuilder：未指定版本的包不能继承上一个包的 pkg_ver。
set -euo pipefail
[[ -f Makefile ]] || { echo '❌ 缺少 ImageBuilder Makefile' >&2; exit 1; }
patched=$(mktemp)
trap 'rm -f "$patched"' EXIT
awk '
    BEGIN {
        old = "$(if $(findstring =,$(pkg)),$(eval pkg_ver:==$(lastword $(subst =, ,$(pkg)))))"
        fixed = "$(eval pkg_ver:=$(if $(findstring =,$(pkg)),=$(lastword $(subst =, ,$(pkg)))))"
    }
    /^define FormatPackages$/ { in_format = 1 }
    in_format && index($0, old) {
        pos = index($0, old)
        $0 = substr($0, 1, pos - 1) fixed substr($0, pos + length(old))
    }
    /^endef$/ { in_format = 0 }
    { print }
' Makefile > "$patched"
if ! cmp -s Makefile "$patched"; then
    cat "$patched" > Makefile
    echo '✅ 已修复 ImageBuilder APK 版本约束串扰' >&2
fi
