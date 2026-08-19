#!/bin/zsh
# macOS 標準の音声認識を使う文字起こしツールを .app としてビルドする。
# 実体は build-app.sh（.app にする理由もそちらに記載）。
#
# 使い方: build-apple-transcriber.sh [出力先ディレクトリ]
#         既定の出力先は ~/.claude/state/VoiceMemoTranscriber.app

set -u

SCRIPT_DIR="${0:A:h}"
SKILL_DIR="${SCRIPT_DIR:h}"
APP_PATH="${1:-$HOME/.claude/state/VoiceMemoTranscriber.app}"

"$SCRIPT_DIR/build-app.sh" \
  "$SKILL_DIR/src/AppleTranscriber.swift" \
  "$SKILL_DIR/templates/Info.plist.template" \
  "$APP_PATH" \
  "AppleTranscriber" || exit 1

print -r -- ""
print -r -- "  ※ 再ビルドすると署名が変わるため、音声認識の許可を再度求められます。"
