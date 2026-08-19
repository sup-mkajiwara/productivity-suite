#!/bin/zsh
# Swift のソースを .app としてビルドする（このスキルで使う小さなツール用）。
#
# なぜ .app にするのか:
#   macOS の各種許可(TCC)は「アプリバンドル」に紐づく。単体の実行ファイルを
#   シェルや launchd から起動すると許可主体が親プロセスになり、許可が下りない。
#   （音声認識では許可要求の時点でプロセスが強制終了する）
#
# 使い方: build-app.sh <ソース.swift> <Info.plist> <出力先.app> <実行ファイル名>

set -u

SRC="${1:?ソースを指定してください}"
PLIST="${2:?Info.plist を指定してください}"
APP_PATH="${3:?出力先を指定してください}"
EXEC_NAME="${4:?実行ファイル名を指定してください}"

info() { print -r -- "  $*" }
die()  { print -r -- "  ❌ $*"; exit 1 }

[[ -f "$SRC" ]]   || die "ソースが見つかりません: $SRC"
[[ -f "$PLIST" ]] || die "Info.plist が見つかりません: $PLIST"

command -v swiftc   > /dev/null 2>&1 || die "swiftc が必要です（Xcode Command Line Tools: xcode-select --install）"
command -v codesign > /dev/null 2>&1 || die "codesign が見つかりません"

info "ビルドします: $APP_PATH"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" || die "出力先を作成できません: $APP_PATH"
cp "$PLIST" "$APP_PATH/Contents/Info.plist" || die "Info.plist を配置できません"

if ! swiftc -O "$SRC" -o "$APP_PATH/Contents/MacOS/$EXEC_NAME"; then
  rm -rf "$APP_PATH"
  die "ビルドに失敗しました: $SRC"
fi

# 署名しないと TCC が許可を記憶できない（ad-hoc 署名で足りる）
if ! codesign --force --deep --sign - "$APP_PATH" 2>/dev/null; then
  rm -rf "$APP_PATH"
  die "署名に失敗しました"
fi

print -r -- "  ✅ ビルド完了: $APP_PATH"
