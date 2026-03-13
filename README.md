# mzwrt-yun — 云源插件自动编译仓库

[![云源插件自动编译发布](https://github.com/dnssme/mzwrt-yun/actions/workflows/build.yml/badge.svg)](https://github.com/dnssme/mzwrt-yun/actions/workflows/build.yml)

自动拉取指定插件仓库源码，使用 **OpenWrt 24.10.5 SDK** 编译后打包成云源格式并发布 GitHub Release。

与官方源完全兼容，同时包含第三方插件及其所有依赖，**可直接平替官方 opkg 源使用**。

---

## 功能特性

- 🚀 **自动触发**：每周一凌晨自动编译 + 插件配置变更时自动触发
- 🏗️ **11 架构并行**：覆盖 x86_64 / aarch64 / arm / mips / mipsel 所有主流平台
- 📦 **全量编译**：编译所有官方 feeds（base/packages/luci/routing/telephony）+ 自定义插件及其全部依赖
- 🔄 **平替官方源**：输出格式与官方 opkg 源完全兼容，可直接替换官方源地址
- 🔖 **自动发布**：编译成功后自动创建 GitHub Release 并上传产物
- 🛠️ **手动触发**：支持在 Actions 页面手动选择架构并发布
- 🔍 **内核版本追踪**：每次编译自动记录内核版本，帮助用户确认固件兼容性

---

## 目录结构

```
mzwrt-yun/
├── .github/
│   └── workflows/
│       └── build.yml          # GitHub Actions 主工作流
├── config/
│   └── targets.conf           # 编译目标架构与 SDK URL 配置
├── scripts/
│   ├── build.sh               # 本地编译脚本
│   ├── package.sh             # 云源打包脚本
│   └── hooks/                 # 架构自定义 hook 脚本目录
│       ├── _example.sh        # hook 脚本模板（含详细注释）
│       ├── x86_64.sh          # x86_64 架构 hook
│       ├── aarch64_generic.sh # aarch64_generic 架构 hook
│       └── ...                # 其他架构 hook（一架构一文件）
├── plugins.conf               # 插件仓库列表（主要配置入口）
└── README.md
```

---

## 快速上手

### 1. 添加插件

编辑 [`plugins.conf`](./plugins.conf)，支持两种格式：

**【标准格式】单体插件仓库（一行对应一个插件仓库）**

```
# 格式: <插件名> <Git仓库地址> [分支]
luci-app-openclash   https://github.com/vernesong/OpenClash   master
luci-app-passwall    https://github.com/xiaorouji/openwrt-passwall  main
```

**【集合格式】插件集合仓库（一个仓库内含多个插件子目录）**

```
# 格式: repo:<仓库名> <Git仓库地址> [分支] [include=包1,包2,...] [exclude=包3,...]

# 导入整个集合的所有插件:
repo:small-package  https://github.com/kenzok8/small-package  main

# 只导入集合中指定的插件（逗号分隔，无空格）:
repo:lienol-pkg     https://github.com/Lienol/openwrt-package  main  include=luci-app-ssr-musl-full,luci-theme-argon

# 导入集合并排除特定包（如避免 Rust 编译问题）:
repo:kiddin9-pkgs   https://github.com/kiddin9/openwrt-packages  main  exclude=shadowsocks-rust,naiveproxy
```

集合格式说明：
- 自动扫描仓库中所有含 `Makefile` 的子目录，识别有效的 OpenWrt 包并以符号链接导入
- `include=` 只导入指定包（留空则导入全部）
- `exclude=` 跳过指定包（常用于排除会导致 CI 失败的 Rust 相关包）
- 包名冲突时，已存在的单体插件优先，集合中的同名包会被跳过

提交后，GitHub Actions 会自动触发所有架构的编译。

### 2. 手动触发编译

在仓库的 **Actions → 云源插件自动编译发布 → Run workflow** 中：
- 选择目标架构（留空则编译所有 11 种架构）
- 选择是否发布 Release

### 3. 架构自定义脚本（补丁 / 环境变量）

每个架构对应一个 hook 脚本，路径为 `scripts/hooks/<架构名>.sh`。  
脚本在插件克隆完成之后、feeds 安装之前执行，适合：

- 向 SDK 或插件源码应用补丁
- 设置特定架构的编译环境变量
- 安装额外的系统依赖

**示例：为 x86_64 应用 SDK 补丁**

```bash
# scripts/hooks/x86_64.sh
patch -d "$SDK_DIR" -p1 < "$GITHUB_WORKSPACE/patches/my-sdk-fix.patch"
```

**示例：设置持久化环境变量（GitHub Actions）**

```bash
# scripts/hooks/aarch64_cortex-a53.sh
echo "EXTRA_CFLAGS=-march=cortex-a53" >> "$GITHUB_ENV"
```

**示例：在本地 build.sh 中设置环境变量**

```bash
# scripts/hooks/mipsel_24kc.sh
export EXTRA_CFLAGS="-mips32r2 -msoft-float"
```

可用的环境变量：

| 变量 | 说明 |
|------|------|
| `$SDK_DIR` | OpenWrt SDK 目录（如 `/tmp/openwrt-sdk`） |
| `$CUSTOM_PKG_DIR` | 已克隆的插件源码目录（如 `/tmp/custom_packages`） |
| `$ARCH` | 当前架构名称（如 `x86_64`） |
| `$GITHUB_ENV` | GitHub Actions 环境变量文件（写入后对后续步骤生效） |
| `$GITHUB_WORKSPACE` | 仓库根目录路径 |

详细使用说明参见 [`scripts/hooks/_example.sh`](./scripts/hooks/_example.sh)。

### 4. 使用编译产物

从 [Releases](../../releases) 页面下载对应架构的 `.tar.gz` 包：

**方式一：直接安装 ipk（推荐）**

```bash
# 解压后将 ipk 文件上传到路由器 /tmp 目录，然后执行：
opkg install /tmp/luci-app-xxx_*.ipk
```

**方式二：作为 opkg 自定义源（可平替官方源）**

编译产物包含完整的官方 feeds 包 + 第三方插件，格式与官方 opkg 源完全兼容。  
将发布包解压到可通过 HTTP 访问的服务器目录后，在路由器上执行：

```bash
# 1. 在路由器上添加自定义源（packages 目录为解压后的 <arch>/packages）
echo "src/gz mzwrt-yun http://<your-server>/<arch>/packages" >> /etc/opkg/customfeeds.conf

# 2. 更新并安装插件
opkg update
opkg install luci-app-openclash
opkg install luci-app-passwall
# ... 其他插件名称见 Release notes 中的插件列表
```

**方式三：通过 GitHub Releases 作为在线源**

如果你的路由器可以访问 GitHub，可以直接使用 Release 资产地址：

```bash
# 将对应架构的 packages 目录发布后，在路由器上添加：
# 注意：需要先将 .tar.gz 解压到可通过 HTTP 访问的目录
echo "src/gz mzwrt-yun http://<your-server>/<arch>/packages" >> /etc/opkg/customfeeds.conf
opkg update
opkg install <插件名>
```

> **说明**：编译时使用了 `CONFIG_ALL_NONSHARED=y`，会编译所有官方 feeds（base/packages/luci/routing/telephony）中的用户空间包以及所有第三方插件及其依赖，输出格式与官方 opkg 源完全兼容，可直接替换官方源地址使用。

---

## ⚠️ 内核版本一致性（重要）

### 问题说明

OpenWrt 的软件包分为两类，两者对版本一致性要求不同：

| 包类型 | 示例 | 版本要求 |
|--------|------|---------|
| 用户空间包 | `luci-app-*`、服务类 | 相同架构即可安装 |
| **内核模块** | **`kmod-*`** | **必须与目标固件内核版本完全一致** |

### 根本原因

OpenWrt SDK 在构建时已绑定特定的内核版本（例如 Linux 6.6.68）。  
编译出的 `kmod-*` 包中包含此内核版本的哈希值（`LINUX_KMOD_SUFFIX`）。  
当你在路由器上执行 `opkg install kmod-xxx.ipk` 时，opkg 会检查该哈希值是否与  
当前运行固件的内核哈希值一致，**不一致则拒绝安装**，报错如：

```
Collected errors:
 * satisfy_dependencies_for: Cannot satisfy the following dependencies for kmod-xxx:
 *      kernel (= 6.6.68-r0+...)
```

### 如何确保版本一致

**第一步：确认路由器固件版本**

在路由器上执行以下任一命令：

```bash
opkg info kernel      # 输出 Version 字段即为当前内核版本
cat /proc/version     # 完整内核版本字符串
ubus call system board # 显示 OpenWrt 版本信息（含 kernel_version 字段）
```

示例输出（OpenWrt 24.10.5）：

```
Package: kernel
Version: 6.6.68-r0+...
```

**第二步：确认编译产物版本**

每次发布的 Release notes 中都包含本次编译所用的 OpenWrt 版本和内核版本：

```
OpenWrt 版本: 24.10.5
内核版本: 6.6.68
```

**第三步：两者必须匹配**

| 场景 | 结论 |
|------|------|
| 路由器固件 = OpenWrt 24.10.5，下载本仓库 24.10.5 编译包 | ✅ 完全兼容 |
| 路由器固件 = OpenWrt 24.10.1，下载本仓库 24.10.5 编译包 | ⚠️ 用户空间包可用，kmod-* 不兼容 |
| 路由器固件 = OpenWrt 23.05.x，下载本仓库 24.10.5 编译包 | ❌ 不兼容，请使用 23.05.x 编译包 |

**第四步：更新 SDK 版本**

若路由器固件升级到新版本，只需修改 [`build.yml`](.github/workflows/build.yml) 顶部的：

```yaml
env:
  OPENWRT_VER: "24.10.5"   # ← 改为新版本号（如 24.10.6 或 24.11.0）
  SDK_VER: "24.10"
```

以及 [`config/targets.conf`](config/targets.conf) 中所有 SDK URL 中的版本号，  
然后提交即可自动触发新版本的编译。

---

## 支持架构

| 架构 | SDK 目标 | 典型设备 |
|------|---------|---------|
| `x86_64` | x86/64 | PC / 虚拟机 / N100 软路由 |
| `aarch64_generic` | rockchip/armv8 | NanoPi R5S/R4S/R4SE, FriendlyWRT |
| `aarch64_cortex-a53` | mediatek/filogic | 小米 AX3000T, GL-MT6000, BPI-R3, CMCC-RAX3000M |
| `aarch64_cortex-a72` | mvebu/cortexa72 | 树莓派 4 (同架构兼容) |
| `arm_cortex-a7_neon-vfpv4` | ipq40xx/generic | GL-B1300, Linksys EA6350v3, ZTE MF286D |
| `arm_cortex-a9_vfpv3-d16` | mvebu/cortexa9 | Marvell Armada 370/XP |
| `arm_cortex-a15_neon-vfpv4` | ipq806x/generic | Netgear R7800, TP-Link C2600 |
| `mips_24kc` | ath79/generic | TP-Link WR940N, Archer A7/C7 |
| `mipsel_24kc` | ramips/mt7621 | 小米 AC2100/4A-Gigabit, 新路由 Newifi D2 |
| `mipsel_74kc` | ramips/rt3883 | MediaTek MT7620 / Ralink RT3883 系列 |
| `mipsel_mips32` | bcm47xx/generic | Broadcom BCM47xx 路由器 |

---

## 本地编译

```bash
# 安装依赖（Ubuntu/Debian）
sudo apt-get install -y build-essential wget git python3 zstd

# 设置 SDK 地址（以 mipsel_24kc/MT7621 为例）
export SDK_URL="https://downloads.openwrt.org/releases/24.10.5/targets/ramips/mt7621/openwrt-sdk-24.10.5-ramips-mt7621_gcc-13.3.0_musl.Linux-x86_64.tar.zst"
export TARGET_ARCH="mipsel_24kc"
export OUTPUT_DIR="$(pwd)/output"

# 执行编译（脚本会自动检测并打印内核版本）
bash scripts/build.sh

# 打包云源（生成 Packages 索引）
bash scripts/package.sh
```

---

## 触发条件

| 条件 | 说明 |
|------|------|
| `plugins.conf` 变更 | 插件列表更新后自动重新编译 |
| `config/**` 变更 | SDK 配置更新后自动重新编译 |
| `schedule (周一 02:00 UTC)` | 每周定时编译，拉取插件最新代码 |
| 手动 `workflow_dispatch` | 在 Actions 页面按需触发，可指定单一架构 |

---

## License

MIT

