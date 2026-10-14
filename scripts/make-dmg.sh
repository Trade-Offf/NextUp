#!/bin/bash
# 生成给同事的安装包。当前系统把新建磁盘映像挂成只读，所以做成 pkg，而不是 DMG。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Build/Products/Release/NextUp.app"
STAGE="$(mktemp -d /tmp/nextup-pkg-stage.XXXXXX)"
OUT="$ROOT/dist/NextUp.pkg"
NOTE="$ROOT/dist/先看这里.txt"

cleanup() {
  rm -rf "$STAGE"
}
trap cleanup EXIT

if [[ ! -d "$APP" ]]; then
  echo "找不到 Release 构建，开始编译…"
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild -project "$ROOT/NextUp.xcodeproj" -scheme NextUp -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$ROOT/build" build
fi

mkdir -p "$ROOT/dist"
COPYFILE_DISABLE=1 cp -R "$APP" "$STAGE/NextUp.app"
rm -f "$OUT"
pkgbuild \
  --root "$STAGE" \
  --install-location /Applications \
  --identifier com.example.nextup \
  --version 1.0 \
  --ownership recommended \
  "$OUT"

cat > "$NOTE" << 'EOF'
双击 NextUp.pkg，按提示安装。装完后在「应用程序」里打开 Next Up。

需要 macOS 15 或更高。这个安装包没有 Apple 开发者签名，第一次打开可能会被系统拦住。

如果提示无法打开或已损坏：
1. 打开「应用程序」，按住 Control 点 Next Up，选「打开」。
2. 还是不行的话，打开「终端」，粘贴下面这一行后回车：
   xattr -cr /Applications/NextUp.app

打开一次主窗口后，到通知中心底部的「编辑小组件」，搜索 Next Up，添加中号或大号。

每人的任务只存在自己电脑上：
~/Library/Application Support/NextUp/
EOF

echo "已生成 $OUT"
ls -lh "$OUT" "$NOTE"
