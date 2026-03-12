#!/usr/bin/env bash
# =============================================================================
# build.sh — 云源插件本地编译脚本
# 用途: 拉取插件源码、使用 OpenWrt SDK 编译、生成 ipk 包
#
# OpenWrt 版本: 24.10.5  |  SDK 格式: .tar.zst  |  GCC: 13.3.0
#
# 内核版本一致性说明
# ─────────────────
# 使用此脚本编译时，SDK_URL 必须与目标固件版本严格对应。
# 例如：SDK 24.10.5 编译的 kmod-* 包只能安装到 OpenWrt 24.10.5 固件。
#
# 用法示例:
#   SDK_URL="https://downloads.openwrt.org/releases/24.10.5/targets/ramips/mt7621/\
#            openwrt-sdk-24.10.5-ramips-mt7621_gcc-13.3.0_musl.Linux-x86_64.tar.zst" \
#   TARGET_ARCH="mipsel_24kc" \
#   bash scripts/build.sh
# =============================================================================
set -euo pipefail

# --------------------------------------------------------------------------- #
# 全局变量（可通过环境变量覆盖）
# --------------------------------------------------------------------------- #
SDK_URL="${SDK_URL:-}"                  # OpenWrt SDK 下载地址（必须）
TARGET_ARCH="${TARGET_ARCH:-x86_64}"   # 目标架构
BUILD_DIR="${BUILD_DIR:-/tmp/openwrt-sdk}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/output}"
PLUGINS_CONF="${PLUGINS_CONF:-$(dirname "$0")/../plugins.conf}"
JOBS="${JOBS:-$(nproc)}"

# --------------------------------------------------------------------------- #
# 工具函数
# --------------------------------------------------------------------------- #
log()  { echo "[$(date +'%H:%M:%S')] $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# --------------------------------------------------------------------------- #
# 检查依赖
# --------------------------------------------------------------------------- #
check_deps() {
    local deps=(wget tar make git python3 rsync zstd)
    for dep in "${deps[@]}"; do
        command -v "$dep" >/dev/null 2>&1 || die "缺少依赖: $dep (请安装后重试)"
    done
    python3 -c "import elftools" >/dev/null 2>&1 \
        || die "缺少 Python3 模块: pyelftools (请执行: pip install pyelftools 或 apt-get install python3-pyelftools)"
    log "依赖检查通过"
}

# --------------------------------------------------------------------------- #
# 下载并解压 OpenWrt SDK
# 注意: OpenWrt 24.10.x 起 SDK 使用 .tar.zst 格式
# --------------------------------------------------------------------------- #
setup_sdk() {
    [[ -n "$SDK_URL" ]] || die "SDK_URL 未设置，请参考脚本头部注释指定 24.10.5 SDK 地址"

    local sdk_file
    sdk_file=$(basename "$SDK_URL")
    local sdk_tar="/tmp/${sdk_file}"

    log "下载 SDK: $SDK_URL"
    mkdir -p "$BUILD_DIR"
    wget -q --show-progress -O "$sdk_tar" "$SDK_URL"

    log "解压 SDK (zstd 格式)..."
    tar --zstd -xf "$sdk_tar" -C "$BUILD_DIR" --strip-components=1
    rm -f "$sdk_tar"
    log "SDK 就绪: $BUILD_DIR"
}

# --------------------------------------------------------------------------- #
# 读取并显示内核版本（用于版本一致性核查）
# --------------------------------------------------------------------------- #
detect_kernel_version() {
    local kver_file="$BUILD_DIR/include/kernel-version.mk"
    [[ -f "$kver_file" ]] || { log "警告: 未找到 kernel-version.mk，跳过内核版本检测"; return; }

    LINUX_VERSION=$(grep -m1 '^LINUX_VERSION:=' "$kver_file" | awk -F':=' '{gsub(/[[:space:]]/, "", $2); print $2}')
    export LINUX_VERSION

    log "======================================================"
    log "内核版本检测结果"
    log "  SDK 绑定内核版本 : Linux $LINUX_VERSION"
    log "  适用固件版本     : 与此 SDK 对应的 OpenWrt 版本"
    log ""
    log "  ⚠️  kmod-* 包必须与目标固件内核版本完全一致！"
    log "  在路由器上执行 'opkg info kernel' 可查看固件内核版本。"
    log "======================================================"
}

# --------------------------------------------------------------------------- #
# 执行架构自定义 hook 脚本
# 在插件克隆完成之后、feeds 安装之前执行，用于应用补丁和设置环境变量。
# --------------------------------------------------------------------------- #
run_arch_hook() {
    local hook_dir
    hook_dir="$(cd "$(dirname "$0")" && pwd)/hooks"
    local hook_script="${hook_dir}/${TARGET_ARCH}.sh"

    export SDK_DIR="$BUILD_DIR"
    export CUSTOM_PKG_DIR="/tmp/custom_packages"
    export ARCH="$TARGET_ARCH"

    if [[ -f "$hook_script" ]]; then
        log "执行架构自定义脚本: $hook_script"
        # shellcheck source=/dev/null
        source "$hook_script"
    else
        log "未找到架构自定义脚本 $hook_script，跳过"
    fi
}

# --------------------------------------------------------------------------- #
# 配置 feeds（追加自定义插件 feed）
# --------------------------------------------------------------------------- #
setup_feeds() {
    local feeds_file="$BUILD_DIR/feeds.conf.default"
    echo "src-link custom /tmp/custom_packages" >> "$feeds_file"
    log "feeds.conf.default 已追加自定义 feed"
}

# --------------------------------------------------------------------------- #
# 拉取插件源码
# --------------------------------------------------------------------------- #
clone_plugins() {
    local custom_pkg_dir="/tmp/custom_packages"
    mkdir -p "$custom_pkg_dir"

    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        read -r name url branch <<< "$line"
        [[ -z "$name" || -z "$url" ]] && continue
        branch="${branch:-main}"

        log "克隆插件: $name  ($url@$branch)"
        local dest="$custom_pkg_dir/$name"
        if [[ -d "$dest" ]]; then
            git -C "$dest" pull --ff-only
        else
            git clone --depth=1 --branch "$branch" "$url" "$dest" 2>/dev/null \
                || git clone --depth=1 "$url" "$dest"
        fi
    done < "$PLUGINS_CONF"

    log "所有插件克隆完成"
}

# --------------------------------------------------------------------------- #
# 更新并安装 feeds
# --------------------------------------------------------------------------- #
install_feeds() {
    cd "$BUILD_DIR"
    log "更新 feeds ..."
    ./scripts/feeds update -a
    log "安装 feeds ..."
    ./scripts/feeds install -a
}

# --------------------------------------------------------------------------- #
# 生成最小化 .config
# CONFIG_ALL_NONSHARED=y: 编译所有 feeds（官方 + 自定义）中的用户空间包，
# 使输出可平替官方源，包含所有插件依赖。
# --------------------------------------------------------------------------- #
configure_sdk() {
    cd "$BUILD_DIR"
    log "生成编译配置 ..."

    cat > .config <<'DOTCONFIG'
CONFIG_ALL_NONSHARED=y
CONFIG_ALL_KMODS=n
CONFIG_ALL=n
CONFIG_AUTOREMOVE=n
CONFIG_SIGNED_PACKAGES=n
CONFIG_LUCI_LANG_zh_Hans=y
DOTCONFIG

    # 显式标记 plugins.conf 中的插件，确保其优先被包含
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        read -r name _ <<< "$line"
        [[ -z "$name" ]] && continue
        echo "CONFIG_PACKAGE_${name}=y" >> .config
    done < "$PLUGINS_CONF"

    make defconfig

    # ⚠️ 在 defconfig 之后禁用已知会导致编译失败的包。
    # 必须在 make defconfig 之后操作，因为 CONFIG_ALL_NONSHARED=y
    # 会在 defconfig 时覆盖 .config 中预先写入的 =n 设置。
    #
    # rust 1.89.0: bootstrap 在 CI 中因 llvm.download-ci-llvm=true 被禁止而 panic。
    # shadowsocks-rust: 依赖 Rust 交叉编译，CI runner 缺少 musl 目标 std 库。
    # uboot-fritz4040: 捆绑的 x86 ELF 解释器在 SDK staging 目录中不存在。
    #
    # 做法：先对每个匹配的符号（含所有变体）添加 "# ... is not set"，
    #   再删除原有的 =y 行，确保所有变体均被显式禁用。
    for pkg in rust shadowsocks-rust uboot-fritz4040; do
        grep "^CONFIG_PACKAGE_${pkg}" .config \
            | sed 's/=.*//' \
            | sed 's/^/# /' \
            | sed 's/$/ is not set/' >> .config || true
        sed -i "/^CONFIG_PACKAGE_${pkg}/d" .config
    done

    log "配置完成"
}

# --------------------------------------------------------------------------- #
# 执行编译（并行 → 单线程降级）
# 使用 PIPESTATUS[0] 获取 make 的真实退出码，避免 tee 掩盖编译失败。
# --------------------------------------------------------------------------- #
compile_packages() {
    cd "$BUILD_DIR"
    log "开始编译 (jobs=$JOBS) ..."
    set +e; make package/compile -j"$JOBS" V=s 2>&1 | tee /tmp/build.log; BUILD_RC=${PIPESTATUS[0]}; set -e
    if [ "$BUILD_RC" -eq 0 ]; then
        log "并行编译成功"
    else
        log "并行编译失败，降级为单线程重试..."
        set +e; make package/compile -j1 V=s 2>&1 | tee /tmp/build.log; BUILD_RC=${PIPESTATUS[0]}; set -e
        [ "$BUILD_RC" -eq 0 ] || die "单线程编译失败，请检查 /tmp/build.log"
    fi
    log "编译完成"
}

# --------------------------------------------------------------------------- #
# 收集 ipk 包
# --------------------------------------------------------------------------- #
collect_packages() {
    mkdir -p "$OUTPUT_DIR/packages"
    log "收集 ipk 文件 ..."

    find "$BUILD_DIR/bin/packages" -name "*.ipk" \
        -exec cp -v {} "$OUTPUT_DIR/packages/" \;

    local count
    count=$(find "$OUTPUT_DIR/packages" -name "*.ipk" | wc -l)
    log "共收集 $count 个 ipk 包"

    if [[ -n "${LINUX_VERSION:-}" ]]; then
        echo "$LINUX_VERSION" > "$OUTPUT_DIR/kernel-version.txt"
        log "内核版本已记录: $OUTPUT_DIR/kernel-version.txt"
    fi
}

# --------------------------------------------------------------------------- #
# 主流程
# --------------------------------------------------------------------------- #
main() {
    log "====== 云源插件编译开始 (OpenWrt 24.10.5) ======"
    check_deps
    setup_sdk
    detect_kernel_version
    clone_plugins
    setup_feeds
    install_feeds
    run_arch_hook
    configure_sdk
    compile_packages
    collect_packages
    log "====== 编译完成，输出目录: $OUTPUT_DIR ======"
}

main "$@"
