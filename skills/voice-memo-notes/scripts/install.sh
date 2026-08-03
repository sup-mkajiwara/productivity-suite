#!/bin/zsh
# voice-memo-notes のセットアップ。
#   - whisper.cpp / ffmpeg の導入
#   - 文字起こしモデルのダウンロード
#   - 設定ファイル・フォルダの作成
#   - launchd による自動監視の登録（任意）
#
# 何度実行しても安全（既にあるものはスキップする）。

set -u

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

SCRIPT_DIR="${0:A:h}"
SKILL_DIR="${SCRIPT_DIR:h}"

CONFIG_DIR="$HOME/.claude/config"
CONFIG_PATH="${VOICE_MEMO_CONFIG:-$CONFIG_DIR/voice-memo-config.json}"
TEMPLATE_PATH="$SKILL_DIR/voice-memo-config.json.template"
PLIST_TEMPLATE="$SKILL_DIR/templates/com.user.voice-memo-notes.plist.template"
LABEL="com.user.voice-memo-notes"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_PATH="$HOME/.claude/logs/voice-memo-notes.launchd.log"

MODEL_NAME="ggml-large-v3-turbo.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL_NAME"

info() { print -r -- "  $*"; }
step() { print -r -- ""; print -r -- "▶ $*"; }
warn() { print -r -- "  ⚠️  $*"; }
ok()   { print -r -- "  ✅ $*"; }
die()  { print -r -- "  ❌ $*"; exit 1; }

ask_yes() {
  local answer
  print -n -- "  $1 [y/N]: "
  read -r answer
  [[ "$answer" == "y" || "$answer" == "Y" ]]
}

print -r -- "=========================================="
print -r -- " voice-memo-notes セットアップ"
print -r -- "=========================================="

# --- 1. 依存コマンド ----------------------------------------------------------
step "1/5 依存コマンドを確認します"

command -v brew > /dev/null 2>&1 || die "Homebrew が必要です: https://brew.sh"

for pkg in whisper-cpp ffmpeg; do
  case "$pkg" in
    whisper-cpp) probe=whisper-cli ;;
    ffmpeg)      probe=ffmpeg ;;
  esac
  if command -v "$probe" > /dev/null 2>&1; then
    ok "$pkg は導入済み（$(command -v $probe)）"
  else
    info "$pkg をインストールします（数分かかります）"
    brew install "$pkg" || die "$pkg のインストールに失敗しました"
    ok "$pkg を導入しました"
  fi
done

# --- 2. モデル ----------------------------------------------------------------
step "2/5 文字起こしモデルを確認します"

MODEL_DIR="$HOME/.cache/whisper.cpp"
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"
mkdir -p "$MODEL_DIR"

if [[ -f "$MODEL_PATH" ]]; then
  ok "モデルは既にあります（$(du -h "$MODEL_PATH" | cut -f1)）: $MODEL_PATH"
else
  info "モデル $MODEL_NAME（約 1.6GB）をダウンロードします"
  info "保存先: $MODEL_PATH"
  if ! curl -fL --progress-bar -o "$MODEL_PATH.part" "$MODEL_URL"; then
    rm -f "$MODEL_PATH.part"
    die "モデルのダウンロードに失敗しました"
  fi
  mv "$MODEL_PATH.part" "$MODEL_PATH"
  ok "モデルを保存しました"
fi

# --- 3. 設定ファイル ----------------------------------------------------------
step "3/5 設定ファイルを用意します"

mkdir -p "$CONFIG_DIR"
if [[ -f "$CONFIG_PATH" ]]; then
  ok "設定ファイルは既にあります: $CONFIG_PATH"
else
  [[ -f "$TEMPLATE_PATH" ]] || die "テンプレートが見つかりません: $TEMPLATE_PATH"
  cp "$TEMPLATE_PATH" "$CONFIG_PATH"
  ok "設定ファイルを作成しました: $CONFIG_PATH"
  info "取り込み元・出力先を変えたい場合はこのファイルを編集してください"
fi

# 設定から必要なフォルダを読み出す（jq 非依存）
# フォルダ名に空白が含まれても崩れないよう、区切りにタブを使う
IFS=$'\t' read -r SOURCE_MODE WATCH_DIR OUTPUT_DIR ARCHIVE_DIR <<< "$(python3 - "$CONFIG_PATH" <<'PY'
import json, os, sys
with open(sys.argv[1], encoding="utf-8") as f:
    cfg = json.load(f)
def get(path, default=""):
    cur = cfg
    for key in path.split("."):
        if not isinstance(cur, dict) or key not in cur:
            return default
        cur = cur[key]
    return default if cur is None else cur
print("\t".join([
    get("source.mode", "export"),
    os.path.expanduser(get("source.watch_dir", "~/Documents/VoiceMemoInbox")),
    os.path.expanduser(get("output.dir", "~/Documents/Obsidian Vault/会議メモ")),
    os.path.expanduser(get("processed.archive_dir", "")),
]))
PY
)"

step "4/5 フォルダを作成します"
for d in "$WATCH_DIR" "$OUTPUT_DIR" "$ARCHIVE_DIR" "$HOME/.claude/state" "$HOME/.claude/logs"; do
  [[ -z "$d" ]] && continue
  if [[ -d "$d" ]]; then
    ok "既にあります: $d"
  else
    mkdir -p "$d" && ok "作成しました: $d"
  fi
done

chmod +x "$SCRIPT_DIR/transcribe.sh" "$SCRIPT_DIR/voice-memo-watch.sh" 2>/dev/null

# プラグインの実体パスはバージョンごとに変わるため、固定パスから呼べるようリンクを張る。
# Skill 本体・launchd はこのリンク経由で呼び出す。
LINK_DIR="$HOME/.claude/scripts"
mkdir -p "$LINK_DIR"
ln -sf "$SCRIPT_DIR/transcribe.sh"        "$LINK_DIR/voice-memo-transcribe.sh"
ln -sf "$SCRIPT_DIR/voice-memo-watch.sh"  "$LINK_DIR/voice-memo-watch.sh"
ok "コマンドのリンクを作成しました: $LINK_DIR/voice-memo-{transcribe,watch}.sh"

# --- 5. 自動監視の登録 --------------------------------------------------------
step "5/5 自動監視（launchd）を登録します"

if [[ "$SOURCE_MODE" == "voicememos" ]]; then
  warn "source.mode が 'voicememos' です。ボイスメモ本体を直接読むには"
  warn "「システム設定 → プライバシーとセキュリティ → フルディスクアクセス」で"
  warn "ターミナル（または Claude Code）を許可する必要があります。"
fi

if [[ ! -f "$HOME/.claude/voice-memo-token" && ! -f "$HOME/.claude/morning-token" ]]; then
  warn "自動実行用のトークンがありません。以下を実行して保存してください:"
  warn "  claude setup-token"
  warn "  # 表示されたトークンを ~/.claude/voice-memo-token に保存し chmod 600"
  warn "（トークンが無いと launchd からの自動実行は失敗します）"
fi

if [[ -f "$PLIST_PATH" ]]; then
  ok "launchd 設定は既にあります: $PLIST_PATH"
  info "監視フォルダを変えた場合は、いったん削除して再登録してください:"
  info "  launchctl bootout gui/\$(id -u)/$LABEL && rm $PLIST_PATH"
else
  if ask_yes "監視フォルダ「$WATCH_DIR」を自動監視するよう登録しますか？"; then
    [[ -f "$PLIST_TEMPLATE" ]] || die "plist テンプレートが見つかりません: $PLIST_TEMPLATE"
    mkdir -p "${PLIST_PATH:h}"
    python3 - "$PLIST_TEMPLATE" "$PLIST_PATH" "$LABEL" \
      "$LINK_DIR/voice-memo-watch.sh" "$WATCH_DIR" "$LOG_PATH" <<'PY'
import sys
tpl, out, label, script, watch, logpath = sys.argv[1:7]
with open(tpl, encoding="utf-8") as f:
    body = f.read()
for key, value in (("__LABEL__", label), ("__SCRIPT_PATH__", script),
                   ("__WATCH_DIR__", watch), ("__LOG_PATH__", logpath)):
    body = body.replace(key, value)
with open(out, "w", encoding="utf-8") as f:
    f.write(body)
PY
    ok "作成しました: $PLIST_PATH"
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
    if launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null; then
      ok "自動監視を有効にしました"
    else
      warn "launchctl の登録に失敗しました。手動で実行してください:"
      warn "  launchctl bootstrap gui/\$(id -u) $PLIST_PATH"
    fi
  else
    info "自動監視は登録しませんでした（後から install.sh を再実行できます）"
  fi
fi

print -r -- ""
print -r -- "=========================================="
print -r -- " セットアップ完了"
print -r -- "=========================================="
print -r -- ""
print -r -- "使い方:"
print -r -- "  1. ボイスメモで録音する"
if [[ "$SOURCE_MODE" == "export" ]]; then
  print -r -- "  2. 「共有 → ファイルに保存」で次のフォルダに書き出す"
  print -r -- "     $WATCH_DIR"
  print -r -- "  3. 自動で文字起こしされ、会議メモが作成される"
else
  print -r -- "  2. 録音を終えると自動で文字起こしされ、会議メモが作成される"
fi
print -r -- "     出力先: $OUTPUT_DIR"
print -r -- ""
print -r -- "手動で実行する場合:"
print -r -- "  Claude Code で  /voice-memo-notes"
print -r -- "  シェルから      $LINK_DIR/voice-memo-watch.sh"
print -r -- ""
print -r -- "ログ: $HOME/.claude/logs/voice-memo-notes.log"
