# p10-gsi-fix — 华为 P10 GSI 修复模组

KernelSU / KernelSU-Next / Magisk 通用。兼容 **meta-hybrid_mount** 与 **SUSFS**。

## 功能

| # | 功能 | 位置 | 说明 |
|---|---|---|---|
| 1 | **恢复华为真实设备身份** | `post-fs-data.sh` + `device.conf` | GSI 把 `ro.product.*` 改成 `TrebleDroid with GApps` / `tdgsi_arm64_ab` / `google`，本模组还原成华为原厂值 |
| 2 | 触摸屏左右边缘无响应 | `service.sh` | 停 `aptouch` (华为触摸优化丢弃边缘坐标) |
| 3 | 外放节点权限 | `service.sh` | `/dev/nxp_smartpa_dev`、`/dev/maxim_smartpa_dev` 设 `root:audio 0660` |
| 4 | GPU 稳定性 | `service.sh` | 默认不动，仅提供按需开关 |
| 5 | SUSFS 隐藏 | `post-fs-data.sh` / `service.sh` | 隐藏模块目录与 overlay 挂载，可关 |

## 恢复的机型信息

取值来源: 原厂 `P10_Stock/product/hw_oem/VTR-AL00/prop/local.prop` 与
`vendor/build.prop` (真机 EMUI 9.1 全量 dump)。

| prop | 原厂值 | GSI 现值 (被改成) |
|---|---|---|
| `ro.product.model` | **VTR-AL00** | TrebleDroid with GApps |
| `ro.product.name` | **VTR-AL00** | lineage_arm64_bgN |
| `ro.product.brand` | **HUAWEI** | google |
| `ro.product.manufacturer` | **HUAWEI** | unknown |
| `ro.product.device` | **HWVTR** | tdgsi_arm64_ab |
| `ro.product.hardwareversion` | **HL1AVTRM** | (空) |
| `ro.product.vendor.*` | 同上 | hi3660 |
| `ro.product.odm.*` | 同上 | Huawei / Chicago |

机型**自动识别**: `device.conf` 里 `MODEL=auto` 时读取 bootloader 传入的
`ro.boot.product.hardware.sku` —— 本机实测为 `VTR-AL00`，无需硬编码。
（注: 用户提到的 `YTR-AL00` 应为 `VTR-AL00` 的笔误；P10 全系为 VTR-*，P10 Plus 为 VKY-*。）

其他版本只需改 `device.conf` 的 `MODEL`:
`VTR-AL00 VTR-TL00 VTR-L09 VTR-L29` (P10) / `VKY-*` (P10 Plus)。

### 默认不动的东西 (风险控制)

- `ro.build.fingerprint` / `ro.build.description` / `ro.build.id` —— 默认**不改**。
  改成华为原厂值会让 Play 认证、GSI OTA 识别、部分应用风控把你当成 EMUI 9。
  要开就设 `SPOOF_FINGERPRINT=1`。
- `ro.product.system.*` / `ro.product.product.*` / `ro.product.system_ext.*` —— 不动，
  它们描述 GSI 自身分区身份，改了容易让系统组件判断错乱。只改全局 + vendor + odm。

## 与 meta-hybrid_mount 的兼容

- 模块使用标准布局 (`system/`、`vendor/` 两个顶层目录)，hybrid_mount 的
  `default_mode="overlay"` / `overlay_mode="ext4"` 直接接管，本模组**不自己 mount**。
- 本模组当前不携带任何覆盖文件 (只有占位文件)，所以挂载阶段实际是空操作；
  身份修改走 `resetprop`，与挂载机制完全解耦，不会与 hybrid_mount 抢顺序。
- 一旦将来放入 stub `.so`，SELinux 标签由 `post-fs-data.sh` 对**模块目录里的源文件**
  设置 (`chcon u:object_r:system_file:s0` / `vendor_file:s0`)。overlay 的标签取自
  源文件 xattr，所以无论 hybrid_mount 何时执行挂载都成立 —— 这是与 hybrid_mount
  配合时最容易踩的坑 (源文件在 /data 上，默认标签是 `data_file`，目标域读不到)。
- 真机当前状态: `/data/adb/modules/` 不存在，即 **hybrid_mount 目前未安装**；
  刷 GSI 后模块目录被清空。装回 hybrid_mount 或直接由 KSU 管理器安装本模组即可。

## 与 SUSFS 的兼容

真机上 `/data/adb/ksu/bin/ksu_susfs` 可用，帮助里确认了相关子命令。
本模组用两条，均失败可忽略、不影响功能:

| 时机 | 命令 | 作用 |
|---|---|---|
| `post-fs-data.sh` | `ksu_susfs add_sus_path <模块目录>` | 让非 su 进程看不到模块目录 |
| `service.sh` | `ksu_susfs hide_sus_mnts_for_non_su_procs` | 隐藏 hybrid_mount 建立的 overlay 挂载 |

关闭: `device.conf` 里 `SUSFS_HIDE=0`。

注意: SUSFS 的 `set_cmdline_or_bootconfig` / `set_uname` 本模组**未使用**，避免与
身份修改叠加产生不一致。身份只通过 resetprop 改属性，SUSFS 只负责隐藏。

## 安装

```
bash build.sh          # 产出 ../dist/p10-gsi-fix-v1.1.0.zip
# KernelSU 管理器 -> 模块 -> 从本地安装 -> 选择 zip -> 重启
```

## 验证

```
su -c 'cat /data/local/tmp/p10-gsi-fix.log'
su -c 'getprop ro.product.model ro.product.brand ro.product.device ro.product.vendor.model'
# 期望: VTR-AL00 / HUAWEI / HWVTR / VTR-AL00
su -c 'getprop init.svc.aptouch'     # 期望 stopped
su -c '/data/adb/ksu/bin/ksu_susfs show'
```

## 卸载

管理器删除模块并重启。`uninstall.sh` 会 `start aptouch`。
身份改动只在内存中，重启后由 GSI 属性自然恢复，无需手动还原。
