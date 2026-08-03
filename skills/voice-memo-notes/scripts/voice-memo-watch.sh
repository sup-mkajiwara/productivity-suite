#!/bin/zsh
# ボイスメモの音声を文字起こしし、Claude Code に会議メモ（Markdown）を生成させる。
# launchd（WatchPaths）から呼び出される。手動実行も可能。

set -u

# /opt/homebrew/bin は whisper-cli / ffmpeg の場所。launchd の最小 PATH には含まれない
export PATH="$HOME/.nodenv/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# launchd 経由だとファイルディスクリプタ上限が 256 と低く、Claude Code(Node) が失敗するため引き上げる
ulimit -n 65536 2>/dev/null || ulimit -n 10240 2>/dev/null || true

SCRIPT_DIR="${0:A:h}"
LOG="${VOICE_MEMO_LOG:-$HOME/.claude/logs/voice-memo-notes.log}"
export VOICE_MEMO_LOG="$LOG"
mkdir -p "${LOG:h}"

log() { print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# 認証: launchd(非対話)では Keychain のログイン情報にアクセスできないため、長期トークンを環境変数で渡す
# トークンは `claude setup-token` で発行し、下記ファイルに保存しておく(chmod 600)
TOKEN_FILE="$HOME/.claude/voice-memo-token"
[[ -f "$TOKEN_FILE" ]] || TOKEN_FILE="$HOME/.claude/morning-token"  # 既存トークンがあれば流用
if [[ -f "$TOKEN_FILE" ]]; then
  export CLAUDE_CODE_OAUTH_TOKEN="$(cat "$TOKEN_FILE")"
fi

# 多重起動の防止（WatchPaths は短時間に複数回発火することがある）
LOCK_DIR="$HOME/.claude/state/voice-memo-notes.lock"
mkdir -p "${LOCK_DIR:h}"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log "他のプロセスが実行中のためスキップします"
  exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT INT TERM

log "===== START ====="

# 文字起こしを実行し、結果(TSV)を受け取る
RESULTS="$("$SCRIPT_DIR/transcribe.sh" "$@")"
STATUS=$?

if (( STATUS != 0 )) && [[ -z "$RESULTS" ]]; then
  log "===== END (文字起こしなし / exit $STATUS) ====="
  exit "$STATUS"
fi

if [[ -z "$RESULTS" ]]; then
  log "===== END (新しい録音はありません) ====="
  exit 0
fi

# 1件 = 1つの会議メモとして Claude に生成させる。
# while にパイプで流し込まないのは、claude が標準入力を読んで残りの行を
# 消費してしまい、2件目以降が処理されなくなるため（配列に展開して回す）。
typeset -a lines
lines=("${(@f)RESULTS}")

for line in "${lines[@]}"; do
  [[ -z "$line" ]] && continue
  IFS=$'\t' read -r txt audio dur recorded_at <<< "$line"
  [[ -z "$txt" ]] && continue
  log "会議メモ生成中: $txt"

  claude -p "/voice-memo-notes

以下の文字起こし結果から会議メモを作成してください。
文字起こしテキストは Read ツールで読み込んでください（このメッセージには貼られていません）。

- 文字起こしテキスト: $txt
- 元の音声ファイル: $audio
- 録音日時: $recorded_at
- 録音長さ(秒): $dur
" \
    --permission-mode acceptEdits \
    --allowedTools "Read" "Write" "Edit" "Bash(ls:*)" "Bash(mkdir:*)" "Bash(date:*)" \
    < /dev/null >> "$LOG" 2>&1 || log "会議メモ生成に失敗しました: $txt"
done

log "===== END ====="
