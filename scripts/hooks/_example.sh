#!/usr/bin/env bash
# =============================================================================
# 架构自定义 hook 脚本示例
# =============================================================================
#
# 使用方法
# ────────
# 将此文件复制并重命名为目标架构名称，例如：
#
#   cp scripts/hooks/_example.sh scripts/hooks/x86_64.sh
#   cp scripts/hooks/_example.sh scripts/hooks/aarch64_cortex-a53.sh
#
# 文件名必须与 config/targets.conf 中的架构名完全一致。
# 当前支持的架构名称：
#   x86_64, aarch64_generic, aarch64_cortex-a53, aarch64_cortex-a72,
#   arm_cortex-a7_neon-vfpv4, arm_cortex-a9_vfpv3-d16, arm_cortex-a15_neon-vfpv4,
#   mips_24kc, mipsel_24kc, mipsel_74kc, mipsel_mips32
#
# 执行时机
# ────────
# 此脚本在以下节点之后、feeds 安装之前执行：
#   - OpenWrt SDK 已解压至 $SDK_DIR
#   - 插件源码已克隆至 $CUSTOM_PKG_DIR
#
# 可执行操作：
#   - 向 SDK 应用补丁
#   - 向克隆的插件源码应用补丁
#   - 安装额外的系统依赖
#   - 设置特定架构的编译环境变量
#
# 环境变量
# ────────
# 以下变量在脚本执行时可用：
#   $SDK_DIR         : OpenWrt SDK 目录（如 /tmp/openwrt-sdk）
#   $CUSTOM_PKG_DIR  : 插件源码目录（如 /tmp/custom_packages）
#   $ARCH            : 当前架构名称（如 x86_64）
#
# 在 GitHub Actions 中持久化环境变量
# ────────────────────────────────────
# 如需将环境变量传递到后续编译步骤，请写入 $GITHUB_ENV：
#
#   echo "MY_VAR=value" >> "$GITHUB_ENV"
#
# 在本地 build.sh 中，直接使用 export 即可（脚本以 source 方式执行）：
#
#   export MY_VAR=value
#
# =============================================================================

# --------------------------------------------------------------------------- #
# 示例：向 SDK 应用补丁
# --------------------------------------------------------------------------- #
# patch_sdk() {
#     local patch_file="${GITHUB_WORKSPACE:-$(pwd)}/patches/my-sdk-fix.patch"
#     if [[ -f "$patch_file" ]]; then
#         echo "[hook] 应用 SDK 补丁: $patch_file"
#         patch -d "$SDK_DIR" -p1 < "$patch_file"
#     fi
# }
# patch_sdk

# --------------------------------------------------------------------------- #
# 示例：向特定插件应用补丁
# --------------------------------------------------------------------------- #
# patch_plugin() {
#     local plugin_dir="$CUSTOM_PKG_DIR/luci-app-openclash"
#     local patch_file="${GITHUB_WORKSPACE:-$(pwd)}/patches/openclash-fix.patch"
#     if [[ -d "$plugin_dir" && -f "$patch_file" ]]; then
#         echo "[hook] 应用插件补丁: $patch_file"
#         patch -d "$plugin_dir" -p1 < "$patch_file"
#     fi
# }
# patch_plugin

# --------------------------------------------------------------------------- #
# 示例：设置编译环境变量
# --------------------------------------------------------------------------- #
# 在 GitHub Actions 中持久化（写入 GITHUB_ENV）
# if [[ -n "${GITHUB_ENV:-}" ]]; then
#     echo "EXTRA_CFLAGS=-march=native" >> "$GITHUB_ENV"
# fi
# 在本地 build.sh 中直接 export
# export EXTRA_CFLAGS="-march=native"

# --------------------------------------------------------------------------- #
# 示例：安装额外依赖（仅 GitHub Actions 环境）
# --------------------------------------------------------------------------- #
# if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
#     sudo apt-get install -y --no-install-recommends some-extra-package
# fi

echo "[hook] _example.sh: 这是示例脚本，请根据需要取消注释并修改上方示例。"
