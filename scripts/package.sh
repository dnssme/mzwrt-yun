#!/usr/bin/env bash
# =============================================================================
# package.sh — 云源打包脚本
# 用途: 将编译好的 ipk 包整理成云源格式并生成包索引
# =============================================================================
set -euo pipefail

OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/output}"
RELEASE_DIR="${OUTPUT_DIR}/release"
ARCH="${TARGET_ARCH:-x86_64}"
TIMESTAMP="$(date +'%Y%m%d%H%M%S')"
VERSION="${VERSION:-${TIMESTAMP}}"

log()  { echo "[$(date +'%H:%M:%S')] $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# --------------------------------------------------------------------------- #
# 生成 opkg 包索引 (Packages / Packages.gz)
# --------------------------------------------------------------------------- #
generate_package_index() {
    local pkg_dir="$1"
    log "生成包索引: $pkg_dir"

    # 使用 opkg-utils 生成索引（优先）；否则手动生成
    if command -v ipkg-make-index >/dev/null 2>&1; then
        ipkg-make-index "$pkg_dir" > "$pkg_dir/Packages"
    else
        # 简单手动生成
        : > "$pkg_dir/Packages"
        for ipk in "$pkg_dir"/*.ipk; do
            [[ -f "$ipk" ]] || continue
            local pkg_name
            pkg_name=$(basename "$ipk" .ipk | sed 's/_[^_]*_[^_]*$//')
            local pkg_size
            pkg_size=$(wc -c < "$ipk")
            local pkg_sha256
            pkg_sha256=$(sha256sum "$ipk" | awk '{print $1}')
            cat >> "$pkg_dir/Packages" <<EOF
Package: $pkg_name
Filename: $(basename "$ipk")
Size: $pkg_size
SHA256sum: $pkg_sha256

EOF
        done
    fi

    gzip -9 -k "$pkg_dir/Packages"
    log "包索引生成完成"
}

# --------------------------------------------------------------------------- #
# 打包云源发布包
# --------------------------------------------------------------------------- #
create_release_archive() {
    mkdir -p "$RELEASE_DIR"

    local arch_dir="$RELEASE_DIR/${ARCH}"
    mkdir -p "$arch_dir"

    # 复制 ipk 包到架构目录
    find "$OUTPUT_DIR/packages" -name "*.ipk" \
        -exec cp {} "$arch_dir/" \;

    # 生成包索引
    generate_package_index "$arch_dir"

    # 创建 tarball
    local tarball="$RELEASE_DIR/mzwrt-yun-plugins-${ARCH}-${VERSION}.tar.gz"
    log "打包云源归档: $(basename "$tarball")"
    tar -czf "$tarball" -C "$RELEASE_DIR" "${ARCH}/"

    # 生成 SHA256 校验文件
    (cd "$RELEASE_DIR" && sha256sum "$(basename "$tarball")" > "$(basename "$tarball").sha256")

    log "云源包已生成: $tarball"
    echo "$tarball"
}

# --------------------------------------------------------------------------- #
# 生成发布摘要
# --------------------------------------------------------------------------- #
generate_summary() {
    local summary_file="$RELEASE_DIR/release-notes.md"
    local pkg_count
    pkg_count=$(find "$OUTPUT_DIR/packages" -name "*.ipk" | wc -l)

    cat > "$summary_file" <<EOF
## 云源插件发布 v${VERSION}

**架构**: \`${ARCH}\`  
**编译时间**: $(date +'%Y-%m-%d %H:%M:%S UTC')  
**插件数量**: ${pkg_count} 个

### 安装方法

将以下地址添加到 OpenWrt 的 opkg 源列表（\`/etc/opkg/customfeeds.conf\`）：

\`\`\`
src/gz mzwrt-yun https://github.com/${GITHUB_REPOSITORY:-<owner/mzwrt-yun>}/releases/latest/download
\`\`\`

然后执行：

\`\`\`bash
opkg update
opkg install <插件名称>
\`\`\`

### 插件列表

EOF

    for ipk in "$OUTPUT_DIR/packages"/*.ipk; do
        [[ -f "$ipk" ]] || continue
        local name
        name=$(basename "$ipk" .ipk | sed 's/_[^_]*_[^_]*$//')
        echo "- \`${name}\`" >> "$summary_file"
    done

    log "发布摘要生成: $summary_file"
}

# --------------------------------------------------------------------------- #
# 主流程
# --------------------------------------------------------------------------- #
main() {
    log "====== 云源打包开始 ======"
    [[ -d "$OUTPUT_DIR/packages" ]] || die "编译输出目录不存在: $OUTPUT_DIR/packages"

    create_release_archive
    generate_summary
    log "====== 打包完成，发布目录: $RELEASE_DIR ======"
}

main "$@"
