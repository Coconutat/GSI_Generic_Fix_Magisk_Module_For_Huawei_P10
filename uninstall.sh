#!/system/bin/sh
# 卸载时恢复原始状态。
# 设备身份不需要手动还原: resetprop 改动只在内存, 重启后由 GSI 自身属性重新填充。
LOG=/data/local/tmp/p10-gsi-fix.log
echo "$(date '+%Y-%m-%d %H:%M:%S') [uninstall] 恢复 aptouch" >> "$LOG"

# 重新拉起被本模组停掉的华为触摸优化服务 (下次开机由 init 自行决定)
start aptouch 2>/dev/null

# 已写入的 SUSFS 规则随模块目录删除失效; 若要立刻生效可手动重启
rm -f "$LOG" 2>/dev/null
