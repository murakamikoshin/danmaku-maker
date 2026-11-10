#!/bin/bash
# 新しいボスの技の、Swift とサーバー(TS)の一致をすばやく調べる(フィクスチャ全件より速い)。
# 使い方: tools/parity.sh <bossLook> "pattern:i:c:v:r,pattern:i:c:v:r,..."
# (通常/覚醒 × 左右反転なし/あり の4通りで、操作なしで最後まで進めた結果を比べる。本番のフィクスチャは FixtureExportTests で作る)
set -e
cd "$(dirname "$0")/.."
rm -f /tmp/parity_swift.json
(cd DanmakuCore && PARITY_LOOK="$1" PARITY_PATTERNS="$2" swift test --filter ParityCheckTests 2>&1 | grep -E "error:|Executed" | head -3)
(cd firebase/functions && npx vitest run test/parity.test.ts 2>&1 | grep -E "Tests |swift .* ts |AssertionError" | head -20)
