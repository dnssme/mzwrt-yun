# mzwrt-yun — 云源插件自动编译仓库

[![云源插件自动编译发布](https://github.com/dnssme/mzwrt-yun/actions/workflows/build.yml/badge.svg)](https://github.com/dnssme/mzwrt-yun/actions/workflows/build.yml)

自动拉取指定插件仓库源码，使用 OpenWrt SDK 编译后打包成云源格式并发布 GitHub Release。

---

## 功能特性

- 🚀 **自动触发**：每周一凌晨自动编译 + 插件配置变更时自动触发
- 🏗️ **多架构并行**：同时编译 x86_64 / aarch64 / mipsel 等主流架构
- 📦 **云源打包**：生成带 `Packages` / `Packages.gz` 索引的 opkg 兼容源
- 🔖 **自动发布**：编译成功后自动创建 GitHub Release 并上传产物
- 🛠️ **手动触发**：支持在 Actions 页面手动选择架构并发布

---

## 目录结构

```
mzwrt-yun/
├── .github/
│   └── workflows/
│       └── build.yml          # GitHub Actions 主工作流
├── config/
│   └── targets.conf           # 编译目标架构配置
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

提交后，GitHub Actions 会自动触发编译。

### 2. 手动触发编译

在仓库的 **Actions → 云源插件自动编译发布 → Run workflow** 中：
- 选择目标架构（留空则编译所有架构）
- 选择是否发布 Release

### 3. 使用编译产物

从 [Releases](../../releases) 页面下载对应架构的 `.tar.gz` 包，解压后：

**方式一：直接安装 ipk**

```bash
opkg install /path/to/luci-app-xxx_*.ipk
```

**方式二：作为 opkg 自定义源**

```bash
# 将包解压到路由器可访问的 HTTP 服务
# 然后添加源
echo "src/gz mzwrt-yun http://<your-server>/<arch>" >> /etc/opkg/customfeeds.conf
opkg update
opkg install <插件名>
```

---

## 支持架构

| 架构 | 目标 | 适用设备 |
|------|------|---------|
| `x86_64` | x86/64 | PC / 虚拟机 / x86 软路由 |
| `aarch64_cortex-a72` | bcm27xx/bcm2711 | 树莓派 4 / ARM64 路由器 |
| `mipsel_24kc` | ramips/mt7621 | Redmi AC2100 / MT7621 路由器 |

如需添加其他架构，修改 [`config/targets.conf`](./config/targets.conf) 和 [`.github/workflows/build.yml`](./.github/workflows/build.yml) 中的 `matrix` 部分。

---

## 本地编译

```bash
# 设置 SDK 地址
export SDK_URL="https://downloads.openwrt.org/releases/23.05.3/targets/x86/64/openwrt-sdk-23.05.3-x86-64_gcc-12.3.0_musl.Linux-x86_64.tar.xz"
export TARGET_ARCH="x86_64"
export OUTPUT_DIR="$(pwd)/output"

# 执行编译
bash scripts/build.sh

# 打包云源
bash scripts/package.sh
```

---

## 触发条件

| 条件 | 说明 |
|------|------|
| `plugins.conf` 变更 | 插件列表更新后自动重新编译 |
| `config/**` 变更 | 配置更新后自动重新编译 |
| `schedule (周一 02:00 UTC)` | 每周定时编译，获取最新代码 |
| 手动 `workflow_dispatch` | 在 Actions 页面按需触发 |

---

## License

MIT
