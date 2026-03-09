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
│   └── package.sh             # 云源打包脚本
├── plugins.conf               # 插件仓库列表（主要配置入口）
└── README.md
```

---

## 快速上手

### 1. 添加插件

编辑 [`plugins.conf`](./plugins.conf)，每行一个插件：

```
# 格式: <插件名> <Git仓库地址> [分支]
luci-app-openclash   https://github.com/vernesong/OpenClash   master
luci-app-passwall    https://github.com/xiaorouji/openwrt-passwall  main
```

提交后，GitHub Actions 会自动触发所有架构的编译。

### 2. 手动触发编译

在仓库的 **Actions → 云源插件自动编译发布 → Run workflow** 中：
- 选择目标架构（留空则编译所有 11 种架构）
- 选择是否发布 Release

### 3. 使用编译产物

从 [Releases](../../releases) 页面下载对应架构的 `.tar.gz` 包：

**方式一：直接安装 ipk（推荐）**

```bash
# 将 ipk 文件上传到路由器 /tmp 目录后执行
opkg install /tmp/luci-app-xxx_*.ipk
```

**方式二：作为 opkg 自定义源**

```bash
# 将包解压到路由器可访问的 HTTP 服务目录
echo "src/gz mzwrt-yun http://<your-server>/<arch>/packages" >> /etc/opkg/customfeeds.conf
opkg update
opkg install <插件名>
```

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

