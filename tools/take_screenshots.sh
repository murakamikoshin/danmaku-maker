#!/bin/bash
# App Store 用スクリーンショットを、iPhone 15 Pro Max シミュレーター（1290×2796）で撮る。
# 使い方: tools/take_screenshots.sh [出力先]   （事前にシミュレーター用にビルド済みであること）
set -u
OUT=${1:-/private/tmp/claude-501/shots}
D=4B3F6407-3E98-4BB1-821A-D2F1965C5F81
to() { perl -e 'alarm shift; exec @ARGV' "$@"; }
APP=$(find ~/Library/Developer/Xcode/DerivedData/DanmakuMaker-*/Build/Products/Debug-iphonesimulator -maxdepth 1 -name "DanmakuMaker.app" | head -1)
mkdir -p "$OUT"
to 900 xcrun simctl bootstatus $D -b >/dev/null 2>&1
to 900 xcrun simctl install $D "$APP" || { echo "install failed"; exit 1; }
shot() { # name lang waitSeconds args...
  local name=$1 lang=$2 wait=$3; shift 3
  to 120 xcrun simctl terminate $D com.koshin.danmakumaker >/dev/null 2>&1
  local loc=en_US; [ "$lang" = ja ] && loc=ja_JP
  to 300 xcrun simctl launch $D com.koshin.danmakumaker -uitest-invincible -AppleLanguages "($lang)" -AppleLocale $loc "$@" >/dev/null
  sleep "$wait"
  to 300 xcrun simctl io $D screenshot "$OUT/${lang}_${name}.png" >/dev/null 2>&1
  echo "shot ${lang}_${name} rc=$?"
}
for L in ja en; do
  shot 01_home $L 8
  shot 02_play_hell $L 24 -open-stage o29
  shot 03_play_boss $L 22 -open-stage o16
  shot 04_editor $L 12 -open-editor
  shot 05_play_fireworks $L 20 -open-stage o19
done
echo ALL_DONE
