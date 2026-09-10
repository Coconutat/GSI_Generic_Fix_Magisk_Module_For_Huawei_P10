#!/system/bin/sh
# P10 GSI 修复模组 —— post-fs-data 阶段
#
# 本阶段职责:
#   1) 恢复华为真实设备身份 (GSI 把 ro.product.* 覆盖成 TrebleDroid/generic)
#   2) 为将来可能放入 system/ vendor/ 的文件打 SELinux 标签
# 运行时机: init 第二阶段, 早于 zygote 与所有 vendor HAL, 属性改动对应用可见。
#
# 兼容: KernelSU (含 KernelSU-Next + SUSFS) 与 Magisk; 文件挂载交给
#       meta-hybrid_mount 时本脚本不做任何 mount, 只打标签与改属性。
MODDIR=${0%/*}
LOG=/data/local/tmp/p10-gsi-fix.log
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [post-fs-data] $*" >> "$LOG"; }

log "==== post-fs-data start ===="

# ---------------------------------------------------------------- resetprop 探测
# KernelSU: /data/adb/ksu/bin/resetprop (ksud applet)
# Magisk  : /data/adb/magisk/resetprop
RP=""
for c in /data/adb/ksu/bin/resetprop /data/adb/magisk/resetprop /system/bin/resetprop; do
    [ -x "$c" ] && RP="$c" && break
done
[ -z "$RP" ] && RP="$(command -v resetprop 2>/dev/null)"
log "resetprop: ${RP:-未找到}"

# resetprop 包装: 优先 -n (不写入 /data/property, ro.* 需要这个)
rp() {
    [ -z "$RP" ] && return 1
    "$RP" -n "$1" "$2" 2>/dev/null && return 0
    "$RP" "$1" "$2" 2>/dev/null && return 0
    return 1
}

# ---------------------------------------------------------------- 读取配置
CONF="$MODDIR/device.conf"
[ -f "$CONF" ] || CONF="$MODDIR/device.conf.example"
cfg() { sed -nE "s/^$1=(.*)$/\1/p" "$CONF" 2>/dev/null | head -1; }

MODEL="$(cfg MODEL)";               [ -n "$MODEL" ] || MODEL=auto
BRAND="$(cfg BRAND)";               [ -n "$BRAND" ] || BRAND=HUAWEI
MANUFACTURER="$(cfg MANUFACTURER)"; [ -n "$MANUFACTURER" ] || MANUFACTURER=HUAWEI
DEVICE="$(cfg DEVICE)";             [ -n "$DEVICE" ] || DEVICE=HWVTR
NAME="$(cfg NAME)";                 [ -n "$NAME" ] || NAME=auto
HWVER="$(cfg HARDWARE_VERSION)"
PART="$(cfg OVERRIDE_PARTITION_PROPS)"; [ -n "$PART" ] || PART=1
SPOOF_FP="$(cfg SPOOF_FINGERPRINT)";    [ -n "$SPOOF_FP" ] || SPOOF_FP=0
SUSFS_HIDE="$(cfg SUSFS_HIDE)";         [ -n "$SUSFS_HIDE" ] || SUSFS_HIDE=1

# auto: 用 bootloader 传进来的真实 sku
if [ "$MODEL" = "auto" ]; then
    MODEL="$(getprop ro.boot.product.hardware.sku)"
    [ -n "$MODEL" ] || MODEL="$(getprop ro.boot.product.model)"
    [ -n "$MODEL" ] || MODEL="VTR-AL00"     # 兜底
    log "MODEL auto -> $MODEL"
fi
[ "$NAME" = "auto" ] && NAME="$MODEL"

log "身份: model=$MODEL name=$NAME brand=$BRAND manufacturer=$MANUFACTURER device=$DEVICE hwver=$HWVER"

# ---------------------------------------------------------------- 写入身份
set_props() {
    prefix="$1"      # 空 = 全局; vendor / odm
    for kv in \
        "brand=$BRAND" \
        "manufacturer=$MANUFACTURER" \
        "model=$MODEL" \
        "name=$NAME" \
        "device=$DEVICE"
    do
        key="${kv%%=*}"; val="${kv#*=}"
        if [ "$prefix" = "global" ]; then
            prop="ro.product.$key"
        else
            prop="ro.product.$prefix.$key"
        fi
        rp "$prop" "$val" && log "set $prop=$val"
    done
}

set_props global
if [ "$PART" = "1" ]; then
    set_props vendor
    set_props odm
fi

[ -n "$HWVER" ] && rp ro.product.hardwareversion "$HWVER" && log "set ro.product.hardwareversion=$HWVER"

if [ "$SPOOF_FP" = "1" ]; then
    rp ro.build.fingerprint "HUAWEI/$MODEL/$MODEL:9/PPR1.180610.011/root202204211128:user/release-keys"
    rp ro.build.description "$MODEL-user 102.0.0 HUAWEI$MODEL 150-CHN-LGRP1 release-keys"
    rp ro.build.id "HUAWEI$MODEL"
    log "fingerprint/description/id 已改写 (SPOOF_FINGERPRINT=1)"
fi

# ---------------------------------------------------------------- SELinux 标签
# 本模组当前不携带需要覆盖的二进制 (GPU stub 见 README 的按需启用)。
# 一旦往 system/ 或 vendor/ 放了文件, 必须在这里打标签, 否则目标域读不到:
#   chcon u:object_r:system_file:s0 "$MODDIR/system/lib64/xxx.so"
#   chcon u:object_r:vendor_file:s0 "$MODDIR/vendor/lib64/xxx.so"
# 原因: 模块文件物理位于 /data (f2fs, seclabel), 无论由 meta-hybrid_mount 还是
#       内核内建机制挂载, 覆盖层的标签都取自这里设置的 xattr。
# 标签定义可查真机 /vendor/etc/selinux/vendor_file_contexts。
n=0
for f in "$MODDIR"/system/lib64/*.so "$MODDIR"/system/lib/*.so; do
    [ -e "$f" ] || continue
    chcon u:object_r:system_file:s0 "$f" 2>/dev/null
    chmod 0644 "$f" 2>/dev/null
    log "labeled system_file: ${f##*/}"; n=$((n+1))
done
for f in "$MODDIR"/vendor/lib64/*.so "$MODDIR"/vendor/lib/*.so; do
    [ -e "$f" ] || continue
    chcon u:object_r:vendor_file:s0 "$f" 2>/dev/null
    chmod 0644 "$f" 2>/dev/null
    log "labeled vendor_file: ${f##*/}"; n=$((n+1))
done
log "打标签文件数: $n"

# ---------------------------------------------------------------- SUSFS 隐藏 (可选)
# SUSFS 的 add_sus_path: 让非 su 进程在若干 syscall 上看不到该路径。
# 只隐藏本模块目录, 不动系统路径; 失败不影响功能。
if [ "$SUSFS_HIDE" = "1" ] && [ -x /data/adb/ksu/bin/ksu_susfs ]; then
    /data/adb/ksu/bin/ksu_susfs add_sus_path "$MODDIR" >> "$LOG" 2>&1 \
        && log "SUSFS: add_sus_path $MODDIR ok" \
        || log "SUSFS: add_sus_path 失败 (可忽略)"
fi

log "==== post-fs-data end ===="
