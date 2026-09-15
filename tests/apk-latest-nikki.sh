#!/bin/bash
# 离线回归：bash tests/apk-latest-nikki.sh
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin" "$test_dir/fixture/apks"
export FIXTURE_DIR="$test_dir/fixture"
for name in nikki-2026.04.08-r1 luci-app-nikki-1.26.1-r1 \
    luci-i18n-nikki-zh-cn-26.161.56550~95d41dd mihomo-meta-1.19.27 \
    mihomo-alpha-2026.06.10; do
    printf 'fixture apk\n' > "$FIXTURE_DIR/apks/$name.apk"
done
tar -czf "$FIXTURE_DIR/nikki.tar.gz" -C "$FIXTURE_DIR/apks" .
printf '\177ELFfixture core\n' > "$FIXTURE_DIR/mihomo"
gzip -c "$FIXTURE_DIR/mihomo" > "$FIXTURE_DIR/mihomo.gz"
cat > "$test_dir/bin/curl" <<'EOF'
#!/bin/bash
set -eu
url= output=
while (( $# )); do
    case "$1" in
        https://*) url=$1; shift ;;
        --output) output=$2; shift 2 ;;
        --retry|--connect-timeout|--max-time|--write-out) shift 2 ;;
        *) shift ;;
    esac
done
echo "$url" >> "$FIXTURE_DIR/urls"
case "$url" in
    */OpenWrt-nikki/releases/latest)
        printf 'https://github.com/nikkinikki-org/OpenWrt-nikki/releases/tag/v1.26.1' ;;
    */mihomo/releases/latest)
        printf 'https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.31' ;;
    */nikki_*.tar.gz)
        [[ ${FAIL_DOWNLOAD:-0} == 0 ]] || exit 22
        cp "$FIXTURE_DIR/nikki.tar.gz" "$output" ;;
    */mihomo-linux-*.gz) cp "$FIXTURE_DIR/mihomo.gz" "$output" ;;
    *) exit 22 ;;
esac
EOF
chmod +x "$test_dir/bin/curl"
export PATH="$test_dir/bin:$PATH"

new_build() {
    mkdir -p "$test_dir/$1/packages"
    cd "$test_dir/$1"
    cp "$repo/tests/fixtures/imagebuilder-format-packages.mk" Makefile
    printf 'CONFIG_TARGET_ARCH_PACKAGES="%s"\n' "$2" > .config
    printf 'old nikki\n' > packages/nikki-2025.01.01-r1.apk
    printf 'unrelated\n' > packages/other-1.0.apk
    printf 'old index\n' > packages/packages.adb
}

for mapping in 'x86_64:amd64-compatible' 'aarch64_generic:arm64' \
    'aarch64_cortex-a53:arm64' 'arm_cortex-a9:armv7' \
    'mipsel_24kc:mipsle-softfloat' 'mips_mips32:mips-softfloat'; do
    arch=${mapping%:*}
    core_arch=${mapping#*:}
    new_build "$arch" "$arch"
    result=$(bash "$repo/shell/apk-latest-nikki.sh")
    [[ "$result" == *'nikki=2026.04.08-r1'* && "$result" == *'luci-app-nikki=1.26.1-r1'* ]]
    [[ "$result" == *'luci-i18n-nikki-zh-cn=26.161.56550~95d41dd'* && "$result" == *'mihomo-meta=1.19.27'* ]]
    [[ -f packages/other-1.0.apk && ! -f packages/nikki-2025.01.01-r1.apk ]]
    [[ ! -f packages/mihomo-alpha-2026.06.10.apk && ! -f packages/packages.adb ]]
    cmp "$FIXTURE_DIR/mihomo" files/usr/libexec/mihomo
    cmp "$FIXTURE_DIR/mihomo" files/usr/bin/mihomo
    grep -q "mihomo-linux-$core_arch-v1.19.31.gz" files/etc/nikki-build-versions
    grep -q 'MIHOMO_RELEASE=v1.19.31' files/etc/nikki-build-versions
done
new_build snapshot aarch64_generic
NIKKI_BRANCH=SNAPSHOT bash "$repo/shell/apk-latest-nikki.sh" > /dev/null
grep -q 'nikki_aarch64_generic-SNAPSHOT.tar.gz' files/etc/nikki-build-versions

expect_failure() {
    if bash "$repo/shell/apk-latest-nikki.sh" > result 2> error; then
        echo "Expected failure: $PWD" >&2; exit 1
    fi
    [[ ! -s result && ! -e files/usr/libexec/mihomo ]]
    [[ -f packages/nikki-2025.01.01-r1.apk && -f packages/packages.adb ]]
}
new_build unsupported unknown_arch
expect_failure
new_build download_failure x86_64
export FAIL_DOWNLOAD=1
expect_failure
unset FAIL_DOWNLOAD
new_build corrupt_core x86_64
printf 'not gzip' > "$FIXTURE_DIR/mihomo.gz"
expect_failure
new_build non_elf_core x86_64
printf 'not ELF' | gzip > "$FIXTURE_DIR/mihomo.gz"
expect_failure
new_build missing_apk x86_64
rm "$FIXTURE_DIR/apks/luci-app-nikki-1.26.1-r1.apk"
tar -czf "$FIXTURE_DIR/nikki.tar.gz" -C "$FIXTURE_DIR/apks" .
expect_failure
echo 'PASS: six architectures, SNAPSHOT, version pins, core replacement, and five failure cases'
