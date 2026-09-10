#!/system/bin/sh
# P10 GSI 修复模组 —— 启动后动作
# KernelSU (含 KernelSU-Next + SUSFS) / Magisk 通用
# 日志: /data/local/tmp/p10-gsi-fix.log
MODDIR=${0%/*}
LOG=/data/local/tmp/p10-gsi-fix.log
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

log "==== service.sh start ===="

# 等待开机完成
i=0
until [ "$(getprop sys.boot_completed)" = "1" ] || [ "$i" -gt 150 ]; do
    sleep 2
    i=$((i + 1))
done
sleep 5

# ---------------------------------------------------------------- 1) 触摸屏边缘
# 华为 aptouch_daemon (触摸优化) 会丢弃屏幕左右边缘的坐标上报,
# 表现为边缘区域点击/滑动无响应。停掉它即可恢复。
# 该服务若被 init 重新拉起, 这里最多重试 5 次 (间隔 3s)。
for n in 1 2 3 4 5; do
    st="$(getprop init.svc.aptouch)"
    if [ "$st" = "running" ]; then
        stop aptouch
        log "aptouch: stop 请求 #$n (原状态 $st)"
    elif [ -z "$st" ]; then
        log "aptouch: 无此服务, 跳过"
        break
    else
        log "aptouch: 已非 running ($st)"
        break
    fi
    sleep 3
done
log "aptouch 最终状态: $(getprop init.svc.aptouch)"

# ---------------------------------------------------------------- 2) 外放节点权限
# 华为 NXP TFA9872 智能功放节点。部分内核上 GSI 起来后属主不对, 外放无声。
for dev in /dev/nxp_smartpa_dev /dev/maxim_smartpa_dev; do
    if [ -e "$dev" ]; then
        chown root:audio "$dev" 2>/dev/null && chmod 0660 "$dev" 2>/dev/null \
            && log "权限已设置: $dev -> $(ls -l "$dev" 2>/dev/null)"
    fi
done

# ---------------------------------------------------------------- 3) 身份复核
# post-fs-data 已经改过; 这里只记录结果, 便于排查是否有进程回写。
log "身份复核: model=$(getprop ro.product.model) brand=$(getprop ro.product.brand) device=$(getprop ro.product.device)"
log "         vendor.model=$(getprop ro.product.vendor.model) odm.device=$(getprop ro.product.odm.device)"

# ---------------------------------------------------------------- 4) SUSFS 挂载隐藏
# 由 meta-hybrid_mount 建立的 overlay 挂载会出现在 /proc/mounts,
# 用 SUSFS 的 hide_sus_mnts_for_non_su_procs 对非 su 进程隐藏。
# 关闭方式: device.conf 里 SUSFS_HIDE=0
if [ -x /data/adb/ksu/bin/ksu_susfs ]; then
    case "$(sed -nE 's/^SUSFS_HIDE=(.*)$/\1/p' "$MODDIR/device.conf" 2>/dev/null | head -1)" in
        0) log "SUSFS: 已按配置跳过挂载隐藏" ;;
        *)
            /data/adb/ksu/bin/ksu_susfs hide_sus_mnts_for_non_su_procs >> "$LOG" 2>&1 \
                && log "SUSFS: hide_sus_mnts_for_non_su_procs ok" \
                || log "SUSFS: hide_sus_mnts_for_non_su_procs 失败 (可忽略)"
            ;;
    esac
fi

# ---------------------------------------------------------------- 5) GPU (默认不动)
# 默认不做任何修改。只有出现下列症状时才打开对应开关:
#   a) Mali 掉频导致卡顿/掉帧:
#      echo performance > /sys/class/devfreq/gpufreq/governor
#      (或锁下限: echo 400000000 > /sys/devices/platform/e82c0000.mali/devfreq/gpufreq/min_freq)
#   b) 某版 GSI 报 dlopen 缺库 (如 libutilscallstack.so): 把 stub 放到
#      $MODDIR/system/lib64/ 与 $MODDIR/vendor/lib64/, 标签由 post-fs-data.sh 自动打。
#      注: P10 上 Android 13 GSI 实测自带该库, 不需要 stub。
log "服务动作完成"

# ---------------------------------------------------------------- 6) 不处理的问题
# 无 SIM 卡时 com.android.phone 会反复崩 (SubscriptionController 对 subId=-1 写
# siminfo 抛 UnsupportedOperationException)。这是 GSI 框架问题: 实测
# pm disable-user com.android.phone 会让 TelecomServiceImpl 接着崩。
# 正解是在 GSI 源码里给 SubscriptionController.setMccMnc 加 INVALID_SUBSCRIPTION_ID
# 早退, 或换已修复的 GSI 版本。本模组不处理。
log "==== service.sh end ===="
