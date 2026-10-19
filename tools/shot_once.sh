#!/bin/bash
# 1枚だけ撮る。アプリの描画が終わるまで最大15分待つ(遅いシミュレーター用)。
# 使い方: DEVICE=<ID> tools/shot_once.sh <出力PNG> <言語 ja|en> [起動引数...]
set -u
OUT=$1; LANGX=$2; shift 2
D=${DEVICE:-4B3F6407-3E98-4BB1-821A-D2F1965C5F81}
to() { perl -e 'alarm shift; exec @ARGV' "$@"; }
LOC=en_US; [ "$LANGX" = ja ] && LOC=ja_JP
APP=$(find ~/Library/Developer/Xcode/DerivedData/DanmakuMaker-*/Build/Products/Debug-iphonesimulator -maxdepth 1 -name "DanmakuMaker.app" | head -1)
to 600 xcrun simctl install $D "$APP" || { echo "install failed"; exit 1; }
to 120 xcrun simctl terminate $D com.koshin.danmakumaker >/dev/null 2>&1
to 300 xcrun simctl launch $D com.koshin.danmakumaker -uitest-invincible -no-ads -no-debug-overlay -AppleLanguages "($LANGX)" -AppleLocale $LOC "$@" >/dev/null
tmp="$OUT.probe.png"; waited=0
while [ $waited -lt 900 ]; do
  sleep 10; waited=$((waited+10))
  to 60 xcrun simctl io $D screenshot "$tmp" >/dev/null 2>&1
  [ "$(stat -f%z "$tmp" 2>/dev/null || echo 0)" -gt 200000 ] && break
done
sleep 5
to 120 xcrun simctl io $D screenshot "$OUT" >/dev/null 2>&1
rm -f "$tmp"
echo "done $OUT size=$(stat -f%z "$OUT") waited=${waited}s"
