#!/bin/zsh
# macOS 標準の音声認識を使う文字起こしツールを .app としてビルドする。
#
# なぜ .app にするのか:
#   音声認識の利用許可(TCC)は「アプリバンドル」に紐づく。単体の実行ファイルを
#   シェルから起動すると許可主体が親プロセス(ターミナル等)になり許可が下りず、
#   許可要求の時点でプロセスが強制終了してしまう。
#   そのため .app にまとめ、`open -n` で起動する形にしている。
#
# 使い方: build-apple-transcriber.sh [出力先ディレクトリ]
#         既定の出力先は ~/.claude/state/VoiceMemoTranscriber.app

set -u

SCRIPT_DIR="${0:A:h}"
SKILL_DIR="${SCRIPT_DIR:h}"
SRC="$SKILL_DIR/src/AppleTranscriber.swift"
PLIST_TEMPLATE="$SKILL_DIR/templates/Info.plist.template"

APP_PATH="${1:-$HOME/.claude/state/VoiceMemoTranscriber.app}"

info() { print -r -- "  $*" }
die()  { print -r -- "  ❌ $*"; exit 1 }

[[ -f "$SRC" ]] || die "ソースが見つかりません: $SRC"
[[ -f "$PLIST_TEMPLATE" ]] || die "Info.plist テンプレートが見つかりません: $PLIST_TEMPLATE"

command -v swiftc > /dev/null 2>&1 || die "swiftc が必要です（Xcode Command Line Tools: xcode-select --install）"
command -v codesign > /dev/null 2>&1 || die "codesign が見つかりません"

info "ビルドします: $APP_PATH"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" || die "出力先を作成できません: $APP_PATH"
cp "$PLIST_TEMPLATE" "$APP_PATH/Contents/Info.plist" || die "Info.plist を配置できません"

if ! swiftc -O "$SRC" -o "$APP_PATH/Contents/MacOS/AppleTranscriber"; then
  rm -rf "$APP_PATH"
  die "ビルドに失敗しました"
fi

# 署名しないと TCC が許可を記憶できない（ad-hoc 署名で足りる）
if ! codesign --force --deep --sign - "$APP_PATH" 2>/dev/null; then
  rm -rf "$APP_PATH"
  die "署名に失敗しました"
fi

print -r -- "  ✅ ビルド完了: $APP_PATH"
print -r -- ""
print -r -- "  ※ 再ビルドすると署名が変わるため、音声認識の許可を再度求められます。"
