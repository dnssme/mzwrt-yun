#!/usr/bin/env bash
# =============================================================================
# build.sh — 云源插件编译脚本
# 用途: 拉取插件源码、使用 OpenWrt SDK 编译、生成 ipk 包
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
    local deps=(wget tar make git python3 rsync)
    for dep in "${deps[@]}"; do
        command -v "$dep" >/dev/null 2>&1 || die "缺少依赖: $dep"
    done
    log "依赖检查通过"
}

# --------------------------------------------------------------------------- #
# 下载并解压 OpenWrt SDK
# --------------------------------------------------------------------------- #
setup_sdk() {
    [[ -n "$SDK_URL" ]] || die "SDK_URL 未设置，请在 matrix 或环境变量中指定"

    log "下载 SDK: $SDK_URL"
    mkdir -p "$BUILD_DIR"
    local sdk_tar="$BUILD_DIR/sdk.tar.xz"
    wget -q --show-progress -O "$sdk_tar" "$SDK_URL"

    log "解压 SDK ..."
    tar -xJf "$sdk_tar" -C "$BUILD_DIR" --strip-components=1
    rm -f "$sdk_tar"
    log "SDK 就绪: $BUILD_DIR"
}

# --------------------------------------------------------------------------- #
# 配置 feeds
# --------------------------------------------------------------------------- #
setup_feeds() {
    local feeds_file="$BUILD_DIR/feeds.conf.default"
    # 保留官方 feeds，添加自定义插件路径
    cat >> "$feeds_file" <<'EOF'

# 自定义插件 feed（由 build.sh 自动追加）
src-link custom /tmp/custom_packages
EOF
    log "feeds.conf.default 已更新"
}

# --------------------------------------------------------------------------- #
# 拉取插件源码
# --------------------------------------------------------------------------- #
clone_plugins() {
    local custom_pkg_dir="/tmp/custom_packages"
    mkdir -p "$custom_pkg_dir"

    while IFS= read -r line; do
        # 跳过空行和注释
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # 解析字段: <name> <url> [branch]
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
# --------------------------------------------------------------------------- #
configure_sdk() {
    cd "$BUILD_DIR"
    log "生成编译配置 ..."

    # 选中所有自定义 feed 中的软件包
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        read -r name _ <<< "$line"
        [[ -z "$name" ]] && continue
        echo "CONFIG_PACKAGE_${name}=m" >> .config
    done < "$PLUGINS_CONF"

    make defconfig
    log "配置完成"
}

# --------------------------------------------------------------------------- #
# 执行编译
# --------------------------------------------------------------------------- #
compile_packages() {
    cd "$BUILD_DIR"
    log "开始编译 (jobs=$JOBS) ..."
    make package/compile -j"$JOBS" V=s 2>&1 | tee /tmp/build.log \
        || make package/compile -j1 V=s 2>&1 | tee /tmp/build.log
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
}

# --------------------------------------------------------------------------- #
# 主流程
# --------------------------------------------------------------------------- #
main() {
    log "====== 云源插件编译开始 ======"
    check_deps
    setup_sdk
    clone_plugins
    setup_feeds
    install_feeds
    configure_sdk
    compile_packages
    collect_packages
    log "====== 编译完成，输出目录: $OUTPUT_DIR ======"
}

main "$@"
