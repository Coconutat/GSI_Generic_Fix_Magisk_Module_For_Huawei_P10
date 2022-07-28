#!/system/bin/sh
# 请不要硬编码 /magisk/modname/... ; 请使用 $MODDIR/...
# 这将使你的脚本更加兼容，即使Magisk在未来改变了它的挂载点
sleep 15s
chown root:audio /dev/nxp_smartpa_dev
chmod 0660 /dev/nxp_smartpa_dev
stop aptouch
