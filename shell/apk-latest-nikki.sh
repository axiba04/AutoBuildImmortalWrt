#!/bin/bash
# 在 ImageBuilder 根目录运行；stdout 只输出 APK 版本约束，日志写入 stderr。
set -euo pipefail

fail() { echo "❌ Nikki: $*" >&2; exit 1; }
download() {
    curl --fail --location --silent --show-error --retry 3 \
        --connect-timeout 20 --max-time 600 "$1" --output "$2"
}
latest_tag() {
    local repo="$1" url tag
    # 使用 release 重定向，避免匿名 GitHub API 的速率限制。
    url=$(curl --fail --location --silent --show-error --retry 3 \
        --connect-timeout 20 --max-time 120 --output /dev/null \
        --write-out '%{url_effective}' "https://github.com/$repo/releases/latest")
    tag=${url##*/}
    [[ "$url" == "https://github.com/$repo/releases/tag/"* && "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
        || fail "无法识别 $repo 的最新稳定版：$url"
    printf '%s' "$tag"
}

[[ -f .config ]] || fail "请在 ImageBuilder 根目录运行（缺少 .config）"
arch=$(sed -n 's/^CONFIG_TARGET_ARCH_PACKAGES="\([^"]*\)"/\1/p' .config)
[[ -n "$arch" ]] || fail "无法从 .config 读取目标软件包架构"
# 必须读取目标架构，不能使用 Actions runner 的 uname -m。
case "$arch" in
    x86_64) core_arch=amd64-compatible ;;
    aarch64_*) core_arch=arm64 ;;
    arm_cortex-a*) core_arch=armv7 ;;
    mipsel_*) core_arch=mipsle-softfloat ;;
    mips_*) core_arch=mips-softfloat ;;
    *) fail "尚未支持目标架构 $arch 的 Mihomo 核心" ;;
esac
branch=${NIKKI_BRANCH:-openwrt-25.12}
case "$branch" in
    openwrt-25.12|SNAPSHOT) ;;
    *) fail "不支持的 Nikki APK 分支：$branch" ;;
esac

# 旧版 FormatPackages 不会清空 pkg_ver，会把核心版本套到后续系统包。
bash "$(dirname "$0")/apk-fix-imagebuilder.sh"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
nikki_tag=$(latest_tag nikkinikki-org/OpenWrt-nikki)
mihomo_tag=$(latest_tag MetaCubeX/mihomo)
nikki_url="https://github.com/nikkinikki-org/OpenWrt-nikki/releases/download/$nikki_tag/nikki_${arch}-${branch}.tar.gz"
core_url="https://github.com/MetaCubeX/mihomo/releases/download/$mihomo_tag/mihomo-linux-${core_arch}-${mihomo_tag}.gz"
echo "✅ Nikki $nikki_tag / Mihomo $mihomo_tag / $branch / $arch" >&2
echo "下载 Nikki: $nikki_url" >&2
download "$nikki_url" "$work_dir/nikki.tar.gz"
mkdir "$work_dir/apks"
tar -xzf "$work_dir/nikki.tar.gz" -C "$work_dir/apks" --no-same-owner

# 只取所需 APK，排除同一压缩包中的 mihomo-alpha 和其他语言包。
# 同时锁定版本，防止 ImmortalWrt 软件源或第三方包覆盖本次选择。
shopt -s nullglob
pins=()
selected=()
for package in nikki luci-app-nikki luci-i18n-nikki-zh-cn mihomo-meta; do
    matches=("$work_dir/apks/$package-"[0-9]*.apk)
    [[ ${#matches[@]} -eq 1 && -s "${matches[0]}" ]] \
        || fail "$nikki_tag 缺少或包含多个 $package APK（$arch / $branch）"
    filename=${matches[0]##*/}
    version=${filename#"$package-"}
    version=${version%.apk}
    pins+=("$package=$version")
    selected+=("${matches[0]}")
done

echo "下载 Mihomo: $core_url" >&2
download "$core_url" "$work_dir/mihomo.gz"
gzip -t "$work_dir/mihomo.gz"
gzip -dc "$work_dir/mihomo.gz" > "$work_dir/mihomo"
# 不在 x86 runner 上执行 ARM/MIPS 核心，但必须确认下载的是 ELF 可执行文件。
magic=$(od -An -tx1 -N4 "$work_dir/mihomo" | tr -d ' \n')
[[ "$magic" == 7f454c46 ]] || fail "Mihomo 下载结果不是 ELF 可执行文件"

# 所有下载和检查通过后才替换构建输入。保留其他第三方软件包。
mkdir -p packages files/usr/libexec files/usr/bin files/etc
for package in nikki luci-app-nikki luci-i18n-nikki-zh-cn mihomo-meta; do
    old_apks=(packages/"$package-"[0-9]*.apk)
    if (( ${#old_apks[@]} )); then rm -f -- "${old_apks[@]}"; fi
done
cp -- "${selected[@]}" packages/
# 让 ImageBuilder 重新生成本地 APK 索引。
rm -f packages/packages.adb
# 上游 mihomo-meta 安装到 /usr/libexec/mihomo，通过 alternatives 提供 /usr/bin/mihomo。
# FILES 在软件包安装后覆盖核心；同步入口也避免 SSR Plus 的旧核心覆盖 Nikki。
install -m 0755 "$work_dir/mihomo" files/usr/libexec/mihomo
ln -sfn ../libexec/mihomo files/usr/bin/mihomo
core_sha256=$(sha256sum "$work_dir/mihomo" | cut -d ' ' -f 1)
cat > files/etc/nikki-build-versions <<EOF
NIKKI_RELEASE=$nikki_tag
MIHOMO_RELEASE=$mihomo_tag
TARGET_ARCH=$arch
NIKKI_BRANCH=$branch
MIHOMO_SHA256=$core_sha256
NIKKI_URL=$nikki_url
MIHOMO_URL=$core_url
APK_PACKAGES=${pins[*]}
EOF
echo "✅ 已准备最新 Nikki APK 和 Mihomo 核心，版本记录：/etc/nikki-build-versions" >&2
printf '%s\n' "${pins[*]}"
