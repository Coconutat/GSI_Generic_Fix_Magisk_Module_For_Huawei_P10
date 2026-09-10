#!/bin/bash
# 打包 P10 GSI 修复模组为 KSU / Magisk 可直接安装的 zip
set -euo pipefail

SRC="$(cd "$(dirname "$(readlink -f -- "$0")")" && pwd)"
OUT="$(cd "$SRC/.." && pwd)/dist"
NAME="p10-gsi-fix"
VER="$(sed -nE 's/^version=(.*)/\1/p' "$SRC/module.prop")"

mkdir -p "$OUT"
ZIP="$OUT/$NAME-$VER.zip"
rm -f "$ZIP"

cd "$SRC"
zip -r9 "$ZIP" \
    module.prop \
    device.conf \
    customize.sh \
    post-fs-data.sh \
    service.sh \
    uninstall.sh \
    system.prop \
    sepolicy.rule \
    META-INF \
    system \
    vendor \
    -x '*.git*' >/dev/null

echo "生成: $ZIP"
echo "大小: $(du -h "$ZIP" | cut -f1)"
echo
echo "内容:"
unzip -l "$ZIP" | sed -n '4,40p'
