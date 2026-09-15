#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
cd "$test_dir"
cp "$repo/tests/fixtures/imagebuilder-format-packages.mk" Makefile

before=$(make -s --no-print-directory | tr -d '\r')
[[ "$before" == *'libgcc1=1.19.27'* && "$before" == *'firewall4=1.19.27'* ]]
bash "$repo/shell/apk-fix-imagebuilder.sh"
after=$(make -s --no-print-directory | tr -d '\r')
expected='curl nikki=2026.04.08-r1 luci-app-nikki=1.26.1-r1 mihomo-meta=1.19.27 apk-openssl libgcc1 firewall4 libc=1.2.5-r5 kernel=6.12.94-r1
libgcc1 curl mihomo-meta=1.19.27'
[[ "$after" == "$expected" ]] || { printf 'Unexpected package list:\n%s\n' "$after" >&2; exit 1; }
cp Makefile expected.mk
bash "$repo/shell/apk-fix-imagebuilder.sh"
cmp Makefile expected.mk
echo 'PASS: reproduced version leakage; fixed pins, ABI suffixes, repeated calls and idempotency'
