#!/bin/bash
# 在本机终端里生成给同事的 DMG。磁盘映像需要图形会话，不能在后台代理里挂载。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Build/Products/Release/NextUp.app"
STAGE="$(mktemp -d /tmp/nextup-dmg-stage.XXXXXX)"
RW="$(mktemp /tmp/nextup-rw.XXXXXX).dmg"
MOUNT="$(mktemp -d /tmp/nextup-mount.XXXXXX)"
OUT="$ROOT/dist/NextUp.dmg"

cleanup() {
  hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
  rm -rf "$STAGE" "$MOUNT" "$RW"
}
trap cleanup EXIT

if [[ ! -d "$APP" ]]; then
  echo "找不到 Release 构建，开始编译…"
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild -project "$ROOT/NextUp.xcodeproj" -scheme NextUp -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$ROOT/build" build
fi

mkdir -p "$ROOT/dist"
rm -f "$RW"
cp -R "$APP" "$STAGE/NextUp.app"
cat > "$STAGE/先看这里.txt" << 'EOF'
把 Next Up 拖到右边的「应用程序」。

需要 macOS 15 或更高。这个安装包没有 Apple 开发者签名，第一次打开可能会被系统拦住。

如果提示无法打开或已损坏：
1. 打开「应用程序」，按住 Control 点 Next Up，选「打开」。
2. 还是不行的话，打开「终端」，粘贴下面这一行后回车：
   xattr -cr /Applications/NextUp.app

打开一次主窗口后，到通知中心底部的「编辑小组件」，搜索 Next Up，添加中号或大号。

每人的任务只存在自己电脑上：
~/Library/Application Support/NextUp/
EOF

hdiutil create -size 30m -fs HFS+ -volname "Next Up" "$RW"
hdiutil attach "$RW" -mountpoint "$MOUNT" -nobrowse
cp -R "$STAGE/NextUp.app" "$MOUNT/NextUp.app"
cp "$STAGE/先看这里.txt" "$MOUNT/先看这里.txt"
ln -s /Applications "$MOUNT/Applications"
sync
hdiutil detach "$MOUNT"
rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -o "$OUT"
echo "已生成 $OUT"
ls -lh "$OUT"
