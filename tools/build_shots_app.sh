#!/bin/bash
# ストア用スクリーンショットを撮るための、AppsFlyer・メディエーションなし(広告 SDK 11.2.0)のシミュレーター用ビルドを作る。
# この Mac でのビルド確認にも使う。
# (この Mac の Xcode 15.2 では AppsFlyer がリンクできないため。アプリ側は #if canImport(AppsFlyerLib) で何もしない版に切り替わる)
# 使い方: tools/build_shots_app.sh   → /private/tmp/claude-501/shots_dd/Build/Products/Debug-iphonesimulator/DanmakuMaker.app ができる
set -e
cd "$(dirname "$0")/.."
python3 - <<'PY'
import re
s = open('project.yml', encoding='utf-8').read()
s = s.replace("  AppsFlyerLib:\n    url: https://github.com/AppsFlyerSDK/AppsFlyerFramework\n    exactVersion: 7.0.4\n", "")
s = s.replace("      - package: AppsFlyerLib\n        product: AppsFlyerLib\n", "")
# 広告 SDK 13 とメディエーションの部品は Xcode 15.2 でビルドできないので、11.2.0 にして部品を外す(AdsCompat.swift が名前の違いを吸収)
s = s.replace("    exactVersion: 13.12.0\n", "    exactVersion: 11.2.0\n")
s = re.sub(r"  AppLovinAdapter:\n(    .*\n)+?(?=  UnityAdapter:)", "", s)
s = re.sub(r"  UnityAdapter:\n(    .*\n)+", "", s)
s = s.replace("      - package: AppLovinAdapter\n        product: AppLovinAdapterTarget\n", "")
s = s.replace("      - package: UnityAdapter\n        product: UnityAdapterTarget\n", "")
assert 'Adapter' not in s and '11.2.0' in s
s = re.sub(r'^name: .*$', 'name: DanmakuShots', s, count=1, flags=re.M)
assert 'AppsFlyerLib' not in s
open('.shots-project.yml', 'w', encoding='utf-8').write(s)
PY
~/.local/xcodegen-dl/xcodegen/bin/xcodegen --spec .shots-project.yml >/dev/null
xcodebuild -project DanmakuShots.xcodeproj -scheme DanmakuApp -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/claude-501/shots_dd CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD"
rm -rf DanmakuShots.xcodeproj .shots-project.yml
