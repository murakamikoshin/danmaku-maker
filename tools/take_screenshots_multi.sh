#!/bin/bash
# 言語ごとのストア用スクリーンショットを、シミュレーターで撮る(DanmakuShots = AppsFlyer なしのビルドを使う)。
# 使い方: DEVICE=<シミュレーターID> APP=<.app のパス> OUT=<出力先> KINDS="iphone|ipad" LANGS="es de fr pt-BR ru ko zh-Hans zh-Hant" tools/take_screenshots_multi.sh
# 撮り終わったら、必ず xcrun simctl shutdown all(起動したままだと Mac が重くなる)
set -u
D=${DEVICE:?DEVICE を指定}
APP=${APP:?APP を指定}
OUT=${OUT:?OUT を指定}
KIND=${KIND:-iphone}
LANGS=${LANGS:-"es de fr pt-BR ru ko zh-Hans zh-Hant"}
to() { perl -e 'alarm shift; exec @ARGV' "$@"; }
locale_of() { case $1 in es) echo es_ES;; de) echo de_DE;; fr) echo fr_FR;; pt-BR) echo pt_BR;; ru) echo ru_RU;; ko) echo ko_KR;; zh-Hans) echo zh_CN;; zh-Hant) echo zh_TW;; ja) echo ja_JP;; *) echo en_US;; esac; }
mkdir -p "$OUT"
to 900 xcrun simctl bootstatus $D -b >/dev/null 2>&1
to 900 xcrun simctl install $D "$APP" || { echo "install failed"; exit 1; }
shot() { # name lang waitSeconds args...
  local name=$1 lang=$2 wait=$3; shift 3
  [ -s "$OUT/${lang}_${name}.png" ] && { echo "skip ${lang}_${name}"; return; }
  to 120 xcrun simctl terminate $D com.koshin.danmakumaker >/dev/null 2>&1
  to 300 xcrun simctl launch $D com.koshin.danmakumaker -uitest-invincible -no-ads -no-debug-overlay -AppleLanguages "($lang)" -AppleLocale $(locale_of $lang) "$@" >/dev/null
  local tmp="$OUT/.probe.png" waited=0
  while [ $waited -lt 300 ]; do
    sleep 5; waited=$((waited+5))
    to 60 xcrun simctl io $D screenshot "$tmp" >/dev/null 2>&1
    [ "$(stat -f%z "$tmp" 2>/dev/null || echo 0)" -gt 100000 ] && break
  done
  sleep $((wait * ${WAITX:-1}))
  to 300 xcrun simctl io $D screenshot "$OUT/${lang}_${name}.png" >/dev/null 2>&1
  echo "shot ${lang}_${name} rc=$?"
}
for L in $LANGS; do
  shot 01_home $L 6
  shot 02_play_hell $L 16 -open-stage o29
  shot 03_play_boss $L 14 -open-stage o16
  shot 04_editor $L 10 -open-editor
  if [ "$KIND" = ipad ]; then shot 07_shop $L 8 -open-shop; else shot 05_play_fireworks $L 14 -open-stage o19; fi
done
echo ALL_DONE
