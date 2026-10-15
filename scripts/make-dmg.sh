#!/bin/bash
# 生成给同事的压缩包。未签名的 pkg 会被系统拒绝，磁盘映像在这台系统上又挂不成可写，所以只打包应用本身。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/release"
APP="$DERIVED/Build/Products/Release/NextUp.app"
STAGE="$(mktemp -d /tmp/nextup-zip-stage.XXXXXX)"
OUT="$ROOT/dist/NextUp.zip"
NOTE="$ROOT/dist/先看这里.txt"

cleanup() {
  rm -rf "$STAGE"
}
trap cleanup EXIT

if [[ ! -d "$APP" ]]; then
  echo "找不到 Release 构建，开始编译…"
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild -project "$ROOT/NextUp.xcodeproj" -scheme NextUp -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" build
fi

mkdir -p "$ROOT/dist"
rm -rf "$STAGE/NextUp.app"
COPYFILE_DISABLE=1 ditto "$APP" "$STAGE/NextUp.app"
codesign --verify --deep --strict "$STAGE/NextUp.app"
rm -f "$OUT"
ditto -c -k --keepParent "$STAGE/NextUp.app" "$OUT"

cat > "$NOTE" << 'EOF'
解压后，把 Next Up 拖进「应用程序」。

需要 macOS 15 或更高。这个应用没有 Apple 开发者签名，第一次打开可能会被系统拦住。

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
