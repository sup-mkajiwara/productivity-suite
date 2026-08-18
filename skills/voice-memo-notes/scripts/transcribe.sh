#!/bin/zsh
# ボイスメモの音声をローカルで文字起こしする。
#
# エンジンは設定 engine で切り替える:
#   apple   … macOS 標準の音声認識（追加インストール不要・既定）
#   whisper … whisper.cpp（精度優先。brew で whisper-cpp と ffmpeg が必要）
#
# 使い方:
#   transcribe.sh                # 設定の取り込み元フォルダから未処理の音声をすべて処理
#   transcribe.sh <音声ファイル>  # 指定ファイルのみ処理（処理済みでも強制的に実行）
#   transcribe.sh <フォルダ>      # 指定フォルダ内の未処理の音声を処理
#
# 標準出力: 処理した1件ごとに TSV を1行出力する
#   文字起こしtxtのパス \t 元音声のパス \t 長さ(秒) \t 録音日時(YYYY-MM-DD HH:MM)
# 進捗・エラーは標準エラー出力とログファイルへ。

set -u
setopt null_glob extended_glob

# Homebrew は launchd の最小 PATH に含まれないため明示的に追加する
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

CONFIG_PATH="${VOICE_MEMO_CONFIG:-$HOME/.claude/config/voice-memo-config.json}"
LOG_FILE="${VOICE_MEMO_LOG:-$HOME/.claude/logs/voice-memo-notes.log}"
mkdir -p "${LOG_FILE:h}"

log() { print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2; print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

if [[ ! -f "$CONFIG_PATH" ]]; then
  log "設定ファイルが見つかりません: $CONFIG_PATH"
  log "voice-memo-config.json.template をコピーして作成してください"
  exit 1
fi

# --- 設定の読み込み -----------------------------------------------------------
# jq に依存しないよう python3 で shell 変数の代入文を生成し、それを source する
CFG_SH="$(mktemp -t voice-memo-cfg)"
trap 'rm -f "$CFG_SH"' EXIT

if ! python3 - "$CONFIG_PATH" > "$CFG_SH" <<'PY'
import json, os, shlex, sys

with open(sys.argv[1], encoding="utf-8") as f:
    cfg = json.load(f)

def get(path, default=None):
    cur = cfg
    for key in path.split("."):
        if not isinstance(cur, dict) or key not in cur:
            return default
        cur = cur[key]
    return default if cur is None else cur

def emit(name, value, path_like=False):
    if isinstance(value, bool):
        value = "true" if value else "false"
    elif isinstance(value, list):
        value = " ".join(str(v) for v in value)
    value = str(value)
    if path_like:
        value = os.path.expanduser(value)
    print(f"{name}={shlex.quote(value)}")

emit("ENGINE",          get("engine", "apple"))
emit("SOURCE_MODE",     get("source.mode", "export"))
emit("WATCH_DIR",       get("source.watch_dir", "~/Documents/VoiceMemoInbox"), True)
emit("VOICEMEMOS_DIR",  get("source.voicememos_dir",
                            "~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings"), True)
emit("EXTENSIONS",      get("source.extensions", ["m4a", "mp3", "wav", "mp4"]))
emit("MIN_SECONDS",     get("source.min_seconds", 0))
emit("ARCHIVE_DIR",     get("processed.archive_dir", ""), True)
emit("STATE_FILE",      get("processed.state_file", "~/.claude/state/voice-memo-processed.txt"), True)
emit("WORK_DIR",        get("work_dir", "~/.claude/state/voice-memo-work"), True)
emit("OUTPUT_DIR",      get("output.dir", "~/Documents/Obsidian Vault/会議メモ"), True)
# apple エンジン
emit("APPLE_APP",       get("apple.app_path", "~/.claude/state/VoiceMemoTranscriber.app"), True)
emit("APPLE_LOCALE",    get("apple.locale", "ja-JP"))
emit("APPLE_CHUNK",     get("apple.chunk_seconds", 45))
# whisper エンジン
emit("WHISPER_BIN",     get("whisper.bin", "whisper-cli"))
emit("MODEL_PATH",      get("whisper.model", "~/.cache/whisper.cpp/ggml-large-v3-turbo.bin"), True)
emit("LANGUAGE",        get("whisper.language", "ja"))
emit("THREADS",         get("whisper.threads", 8))
emit("TIMESTAMPS",      get("whisper.timestamps", False))
PY
then
  log "設定ファイルの読み込みに失敗しました（JSON 構文を確認してください）: $CONFIG_PATH"
  exit 1
fi

source "$CFG_SH"
rm -f "$CFG_SH"
trap - EXIT

# --- エンジンごとの前提確認 ---------------------------------------------------
case "$ENGINE" in
  apple)
    # 追加インストールは不要。長さの取得は macOS 標準の afinfo を使う
    if ! command -v afinfo > /dev/null 2>&1; then
      log "afinfo が見つかりません（macOS 標準のコマンドです）"
      exit 1
    fi
    if [[ ! -d "$APPLE_APP" ]]; then
      log "文字起こしツールが見つかりません: $APPLE_APP"
      log "→ scripts/install.sh または scripts/build-apple-transcriber.sh を実行してください"
      exit 1
    fi
    ;;
  whisper)
    for cmd in ffmpeg "$WHISPER_BIN"; do
      if ! command -v "$cmd" > /dev/null 2>&1; then
        log "コマンドが見つかりません: $cmd  → scripts/install.sh を実行してください"
        exit 1
      fi
    done
    if [[ ! -f "$MODEL_PATH" ]]; then
      log "whisper モデルが見つかりません: $MODEL_PATH  → scripts/install.sh を実行してください"
      exit 1
    fi
    ;;
  *)
    log "engine が不正です: '$ENGINE'（apple または whisper）"
    exit 1
    ;;
esac

# --- 取り込み元の決定 ---------------------------------------------------------
case "$SOURCE_MODE" in
  export)     SRC_DIR="$WATCH_DIR" ;;
  voicememos) SRC_DIR="$VOICEMEMOS_DIR" ;;
  *) log "source.mode が不正です: '$SOURCE_MODE'（export または voicememos）"; exit 1 ;;
esac

TARGET="${1:-}"
FORCE=0
typeset -a candidates
candidates=()

if [[ -n "$TARGET" ]]; then
  if [[ -f "$TARGET" ]]; then
    # 単一ファイル指定は明示的な指示とみなし、処理済みでも再実行する
    candidates=("$TARGET")
    FORCE=1
  elif [[ -d "$TARGET" ]]; then
    SRC_DIR="$TARGET"
  else
    log "指定されたパスが見つかりません: $TARGET"
    exit 1
  fi
fi

# 出力先(会議メモのフォルダ)はここでは作らない。
# 出力先は Obsidian Vault など ~/Documents 配下に置かれることが多く、
# launchd から起動された場合はアクセスした時点でプロセスが強制終了される（TCC 保護）。
# 会議メモの書き込みは Claude 側が行うため、フォルダ作成もそちらに任せる。
mkdir -p "$WORK_DIR" "${STATE_FILE:h}"
touch "$STATE_FILE"

if (( ${#candidates} == 0 )); then
  if [[ ! -d "$SRC_DIR" ]]; then
    log "取り込み元フォルダがありません: $SRC_DIR"
    if [[ "$SOURCE_MODE" == "voicememos" ]]; then
      log "ボイスメモ本体を直接読むには、ターミナル/Claude Code に「フルディスクアクセス」を付与する必要があります"
    fi
    exit 1
  fi
  for ext in ${=EXTENSIONS}; do
    candidates+=("$SRC_DIR"/**/*.${ext}(.N))
  done
  # アーカイブ先が取り込み元の配下にある場合、処理済みを再取得しないよう除外する
  if [[ -n "$ARCHIVE_DIR" ]]; then
    candidates=(${candidates:#${ARCHIVE_DIR}/*})
  fi
fi

# --- ヘルパー ----------------------------------------------------------------

# 処理済み判定キー: ファイル名 + サイズ + 更新時刻（アーカイブへ移動しても不変）
state_key() {
  local st
  st=$(stat -f '%z:%m' "$1" 2>/dev/null) || return 1
  print -r -- "${1:t}:${st}"
}

# WatchPaths は書き込み完了を待たずに発火するため、サイズが安定するまで待つ
wait_until_stable() {
  local f="$1" prev="" cur i
  for i in {1..30}; do
    cur=$(stat -f '%z' "$f" 2>/dev/null) || return 1
    if [[ "$cur" == "$prev" ]] && (( cur > 0 )); then
      return 0
    fi
    prev="$cur"
    sleep 2
  done
  return 1
}

# 音声の長さ（秒）。afinfo は macOS 標準なので追加インストール不要
duration_seconds() {
  local d
  d=$(afinfo "$1" 2>/dev/null | awk -F': ' '/estimated duration/ {print $2}' | awk '{print $1}')
  [[ -z "$d" ]] && return 1
  printf '%.0f' "$d" 2>/dev/null || return 1
}

# macOS 標準の音声認識で文字起こしする。
# 許可(TCC)がアプリバンドルに紐づくため、`open -n` で .app として起動する必要がある。
# 結果は直接受け取れないので、出力ファイルと .done ファイル経由で待つ。
apple_transcribe() {
  local src="$1" out="$2" dur="$3"
  local done_file="$out.done"
  rm -f "$out" "$done_file"

  if ! open -n -a "$APPLE_APP" --args "$src" "$out" "$APPLE_LOCALE" "$APPLE_CHUNK" 2>> "$LOG_FILE"; then
    log "文字起こしツールを起動できませんでした: $APPLE_APP"
    return 1
  fi

  # 待ち時間は録音の長さに比例させる（実測では音声長の 1/6 程度で完了する）
  local limit=$(( 180 + dur ))
  local waited=0
  while (( waited < limit )); do
    [[ -f "$done_file" ]] && break
    sleep 2
    (( waited += 2 ))
  done

  if [[ ! -f "$done_file" ]]; then
    log "文字起こしが ${limit}秒 以内に終わりませんでした: ${src:t}"
    return 1
  fi

  local code
  code=$(cat "$done_file" 2>/dev/null)
  rm -f "$done_file"

  # ツール側の進捗ログを取り込む
  # （`open` 経由で起動するため標準エラーを直接受け取れず、ファイル経由で渡している）
  if [[ -f "$out.log" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && log "  [文字起こし] $line"
    done < "$out.log"
    rm -f "$out.log"
  fi

  case "$code" in
    0) return 0 ;;
    3) log "音声認識が許可されていません。docs/VOICE_MEMO.md の「音声認識の許可」を確認してください" ;;
    5) log "認識結果が空でした（無音の可能性）: ${src:t}" ;;
    *) log "文字起こしに失敗しました（コード $code）: ${src:t}" ;;
  esac
  return 1
}

# whisper.cpp で文字起こしする
whisper_transcribe() {
  local src="$1" out_base="$2"
  local wav="${out_base}.16k.wav"

  # whisper.cpp は 16kHz モノラル PCM しか受け付けないため変換する
  if ! ffmpeg -nostdin -loglevel error -y -i "$src" -vn -ac 1 -ar 16000 -c:a pcm_s16le "$wav" >> "$LOG_FILE" 2>&1; then
    log "音声変換に失敗しました: $src"
    rm -f "$wav"
    return 1
  fi

  typeset -a wargs
  wargs=(-m "$MODEL_PATH" -f "$wav" -l "$LANGUAGE" -t "$THREADS" -otxt -of "$out_base" -np)
  [[ "$TIMESTAMPS" == "true" ]] && wargs+=(-osrt)

  if ! "$WHISPER_BIN" "${wargs[@]}" >> "$LOG_FILE" 2>&1; then
    log "文字起こしに失敗しました: $src"
    rm -f "$wav"
    return 1
  fi
  rm -f "$wav"
  return 0
}

# 音声1件を文字起こしする。成功時は生成した .txt のパスを標準出力に返す
transcribe_one() {
  local src="$1" dur="$2"
  local base="${${src:t}:r}"
  # パス区切りや空白など扱いに困る文字だけを置換する（日本語のファイル名はそのまま残す）
  local safe="${base//[\/\\:\*\?\"\<\>\|[:space:]]/_}"
  local stamp
  stamp=$(stat -f '%Sm' -t '%Y%m%d-%H%M%S' "$src" 2>/dev/null) || stamp="unknown"
  local out_base="$WORK_DIR/${stamp}_${safe}"

  log "文字起こし中（$ENGINE）: ${src:t}"

  case "$ENGINE" in
    apple)   apple_transcribe "$src" "${out_base}.txt" "$dur" || return 1 ;;
    whisper) whisper_transcribe "$src" "$out_base" || return 1 ;;
  esac

  if [[ ! -s "${out_base}.txt" ]]; then
    log "文字起こし結果が空でした: $src"
    return 1
  fi
  print -r -- "${out_base}.txt"
}

# --- メイン ------------------------------------------------------------------
log "開始: engine=$ENGINE mode=$SOURCE_MODE src=$SRC_DIR 候補=${#candidates}件"

processed=0
skipped=0
failed=0

for src in "${candidates[@]}"; do
  key=$(state_key "$src") || { log "情報取得に失敗: $src"; ((failed++)); continue; }

  if (( ! FORCE )) && grep -qxF -- "$key" "$STATE_FILE" 2>/dev/null; then
    ((skipped++))
    continue
  fi

  if ! wait_until_stable "$src"; then
    log "書き込み完了を待てませんでした（次回に再試行します）: $src"
    ((failed++))
    continue
  fi

  dur=$(duration_seconds "$src") || dur=0
  if (( dur < MIN_SECONDS )); then
    log "短すぎるためスキップ（${dur}秒 < ${MIN_SECONDS}秒）: ${src:t}"
    print -r -- "$key" >> "$STATE_FILE"
    ((skipped++))
    continue
  fi

  # 録音日時はファイルの更新時刻を使う（ボイスメモの録音日時とほぼ一致する）
  recorded_at=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$src" 2>/dev/null) || recorded_at=""

  if ! txt=$(transcribe_one "$src" "$dur"); then
    ((failed++))
    continue
  fi

  # 成功したものだけを処理済みとして記録する（失敗分は次回再試行される）
  grep -qxF -- "$key" "$STATE_FILE" 2>/dev/null || print -r -- "$key" >> "$STATE_FILE"

  audio_path="$src"
  # アーカイブは書き出しフォルダ運用のときだけ行う（ボイスメモ本体は変更しない）
  if [[ -n "$ARCHIVE_DIR" && "$SOURCE_MODE" == "export" && $FORCE -eq 0 ]]; then
    if mkdir -p "$ARCHIVE_DIR" && mv -n "$src" "$ARCHIVE_DIR/"; then
      audio_path="$ARCHIVE_DIR/${src:t}"
      log "アーカイブしました: $audio_path"
    else
      log "アーカイブに失敗しました（元の場所に残します）: $src"
    fi
  fi

  printf '%s\t%s\t%s\t%s\n' "$txt" "$audio_path" "$dur" "$recorded_at"
  ((processed++))
done

log "完了: 文字起こし=${processed}件 スキップ=${skipped}件 失敗=${failed}件"

# 1件も処理できず失敗があった場合のみ異常終了扱いにする
if (( processed == 0 && failed > 0 )); then
  exit 1
fi
exit 0
