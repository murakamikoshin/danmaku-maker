#!/bin/sh
# Xcode Cloud: リポジトリを取得した直後に実行される。
# 1) GoogleService-Info.plist を環境変数から復元（秘密情報扱いなので Git には入れていない）
# 2) XcodeGen で .xcodeproj を作り直す（project.yml が正）
set -e
cd "$CI_PRIMARY_REPOSITORY_PATH"

if [ -n "$GOOGLE_SERVICE_INFO_PLIST_BASE64" ]; then
  echo "$GOOGLE_SERVICE_INFO_PLIST_BASE64" | base64 --decode > DanmakuApp/GoogleService-Info.plist
  echo "GoogleService-Info.plist を復元しました"
else
  echo "警告: GOOGLE_SERVICE_INFO_PLIST_BASE64 が未設定です。オンライン機能のないビルドになります。"
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi
xcodegen generate
