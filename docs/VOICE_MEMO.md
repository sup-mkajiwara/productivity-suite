# ボイスメモ → 会議メモ 自動化ガイド

Mac のボイスメモで録音した音声を、ローカルで文字起こしして
要約付きの会議メモ Markdown を自動生成する仕組みです。

```
ボイスメモ で録音
      ↓  （書き出し or 自動検知）
監視フォルダ
      ↓  launchd が変更を検知
ローカルで文字起こし（macOS 標準の音声認識）
      ↓
Claude Code が要約 → 会議メモ Markdown
      ↓
出力フォルダ（既定: Obsidian Vault/会議メモ）
```

音声は外部に送信されません（要約のみ Claude Code が処理します）。

---

## 文字起こしエンジン

既定は **macOS 標準の音声認識**です。追加のダウンロードは一切ありません。

| | `apple`（既定） | `whisper` |
|---|---|---|
| 追加ダウンロード | **なし** | モデル 75MB〜1.6GB |
| 追加インストール | なし（ビルドに Xcode CLT のみ） | `brew install whisper-cpp ffmpeg` |
| 速度（実測） | **4.5分の音声を約40秒** | モデル次第（large は数倍遅い） |
| 精度 | 実用的。専門用語・固有名詞は誤りやすい | large-v3-turbo は高精度 |
| 初回の許可操作 | **必要**（音声認識の許可ダイアログ） | 不要 |
| 音声の外部送信 | なし（オンデバイス認識を強制） | なし |

精度を上げたい場合は設定の `engine` を `whisper` に変えてください（後述）。

---

## セットアップ

### 1. セットアップスクリプトを実行

```bash
skills/voice-memo-notes/scripts/install.sh
```

以下を自動で行います。

| 内容 | 補足 |
|------|------|
| 設定ファイル作成 | `~/.claude/config/voice-memo-config.json` |
| 文字起こしツールのビルド | `~/.claude/state/VoiceMemoTranscriber.app`（`apple` エンジンのみ） |
| フォルダ作成 | 監視フォルダ・出力フォルダ・アーカイブフォルダ |
| 音声認識の許可 | 許可ダイアログを表示（`apple` エンジンのみ） |
| launchd 登録 | 監視フォルダの変更で自動起動（実行するか確認されます） |

`apple` エンジンには **Xcode Command Line Tools** が必要です（ビルド時のみ）。

```bash
xcode-select --install   # 未導入の場合
```

確認を省いて一気に進めたい場合（Claude Code から実行する場合など）:

```bash
VOICE_MEMO_ASSUME_YES=1 skills/voice-memo-notes/scripts/install.sh
```

### 2. 音声認識の許可

`apple` エンジンでは、初回に macOS の許可ダイアログが表示されるので **「OK」** を選びます。

許可は `~/.claude/state/VoiceMemoTranscriber.app` に紐づいて記憶されるため、
一度許可すれば以降は自動で文字起こしできます。

あとから設定を変えたい場合は
**システム設定 → プライバシーとセキュリティ → 音声認識** を開いてください。

> ⚠️ ツールを**再ビルドすると署名が変わるため、許可を再度求められます**。
> プラグイン更新後に文字起こしが失敗する場合は、`install.sh` を再実行して許可し直してください。

### 3. 自動実行用トークンを設定（自動化する場合のみ）

launchd（非対話実行）では Keychain のログイン情報が使えないため、長期トークンが必要です。

```bash
claude setup-token
# 表示されたトークンを保存
echo '<表示されたトークン>' > ~/.claude/voice-memo-token
chmod 600 ~/.claude/voice-memo-token
```

`~/.claude/morning-token` が既にある場合はそれが自動的に流用されます。

### 4. 動作確認

適当な音声を監視フォルダに置いて、手動実行してみます。

```bash
~/.claude/scripts/voice-memo-watch.sh
tail -f ~/.claude/logs/voice-memo-notes.log
```

---

## 使い方

### パターンA: 書き出しフォルダ運用（既定・推奨）

1. ボイスメモで録音する
2. 録音を選び **共有 → ファイルに保存** で監視フォルダ（既定 `~/Documents/VoiceMemoInbox`）へ書き出す
3. 数十秒〜数分後、出力フォルダに会議メモ `.md` が作成される
4. 処理済みの音声は `_done` フォルダへ移動される

「文字起こししたい録音だけ」を選べるのが利点です。権限設定も不要です。

### パターンB: ボイスメモ本体を直接監視

書き出し操作なしで全録音を自動処理します。設定を変更してください。

```json
{
  "source": {
    "mode": "voicememos"
  }
}
```

**追加で必要な設定:**

- システム設定 → プライバシーとセキュリティ → **フルディスクアクセス** で
  ターミナル（および Claude Code）を許可
- 許可後、`install.sh` を再実行して launchd を登録し直す

> ⚠️ ボイスメモの内部フォルダは Apple の仕様変更で構造が変わる可能性があります。
> 動かなくなった場合は `source.voicememos_dir` を実際のパスに合わせてください。
> このモードでは音声のアーカイブ移動は行いません（本体を変更しないため）。

### 手動実行（Claude Code から）

```
/voice-memo-notes                      # 未処理の録音をすべて処理
/voice-memo-notes ~/Downloads/rec.m4a  # 特定ファイルを処理
/voice-memo-notes ~/Downloads          # 特定フォルダを処理
```

---

## 設定リファレンス

`~/.claude/config/voice-memo-config.json`

```json
{
  "engine": "apple",
  "source": {
    "mode": "export",
    "watch_dir": "~/Documents/VoiceMemoInbox",
    "voicememos_dir": "~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings",
    "extensions": ["m4a", "mp3", "wav", "mp4"],
    "min_seconds": 30
  },
  "processed": {
    "archive_dir": "~/Documents/VoiceMemoInbox/_done",
    "state_file": "~/.claude/state/voice-memo-processed.txt"
  },
  "work_dir": "~/.claude/state/voice-memo-work",
  "apple": {
    "app_path": "~/.claude/state/VoiceMemoTranscriber.app",
    "locale": "ja-JP",
    "chunk_seconds": 45
  },
  "whisper": {
    "bin": "whisper-cli",
    "model": "~/.cache/whisper.cpp/ggml-large-v3-turbo.bin",
    "language": "ja",
    "threads": 8,
    "timestamps": false
  },
  "output": {
    "dir": "~/Documents/Obsidian Vault/会議メモ",
    "filename_format": "{date}_{title}",
    "include_full_text": true,
    "tags": ["会議メモ"]
  }
}
```

| 項目 | 既定値 | 説明 |
|------|--------|------|
| `engine` | `apple` | `apple` = macOS 標準 / `whisper` = whisper.cpp |
| `source.mode` | `export` | `export` = 書き出しフォルダ監視 / `voicememos` = 本体直接監視 |
| `source.watch_dir` | `~/Documents/VoiceMemoInbox` | 監視フォルダ。**変更したら `install.sh` を再実行**（launchd の監視先が変わるため） |
| `source.extensions` | m4a, mp3, wav, mp4 | 対象とする拡張子 |
| `source.min_seconds` | 30 | これ未満の短い録音は無視（メモ的な独り言を除外） |
| `processed.archive_dir` | `<watch_dir>/_done` | 処理済み音声の移動先。空文字にすると移動しない |
| `processed.state_file` | `~/.claude/state/voice-memo-processed.txt` | 処理済み記録。消すと全件が再処理対象になる |
| `work_dir` | `~/.claude/state/voice-memo-work` | 文字起こしテキストの置き場所 |
| `apple.locale` | `ja-JP` | 認識する言語。オンデバイス非対応の言語は拒否されます |
| `apple.chunk_seconds` | 45 | 音声を分割する長さ（後述） |
| `output.dir` | `~/Documents/Obsidian Vault/会議メモ` | **会議メモの出力先** |
| `output.filename_format` | `{date}_{title}` | `{date}` `{time}` `{title}` が使える |
| `output.include_full_text` | `true` | `false` にすると要約のみ（全文を含めない） |

### なぜ音声を分割するのか（`apple.chunk_seconds`）

macOS の音声認識に長い音声をそのまま渡すと、**末尾の一部しか返りません**
（4.5分の音声で最後の30秒程度のみ、という挙動を実測で確認しています）。

そのため 45 秒ごとに分割し、順に認識して連結しています。分割は AVFoundation で
行うため ffmpeg は不要です。既定値のままで問題ありませんが、区切りで単語が
切れるのが気になる場合は 30〜60 秒の範囲で調整してください。

### 録音品質の注意（重要）

`apple` エンジンは**低ビットレートの録音に弱い**ことを実測で確認しています。
同じ内容・同じ音量の音声で比較した結果:

| 録音品質 | 文字起こし結果 |
|---|---|
| 非圧縮（PCM） | 797文字（全文） |
| AAC 64kbps | 797文字（全文・非圧縮と同等） |
| **AAC 32kbps** | **125文字（大半が欠落）** |

ボイスメモの品質設定が「圧縮」だと低ビットレートで保存されます。
**設定 → ボイスメモ → オーディオ品質 を「ロスレス」**にしておくと確実です。

低ビットレートの録音しか手元にない場合は、`engine` を `whisper` に切り替えてください
（whisper は圧縮音声に対して比較的頑健です）。

### 精度を上げたい場合（whisper に切り替え）

```json
{
  "engine": "whisper",
  "whisper": {
    "model": "~/.cache/whisper.cpp/ggml-large-v3-turbo.bin"
  }
}
```

設定を変えてから `install.sh` を再実行すると、`whisper-cpp` / `ffmpeg` の導入と
モデルのダウンロードが行われます。モデルはファイル名から自動で判別されます。

| モデル | サイズ | 目安 |
|--------|--------|------|
| `ggml-tiny.bin` | 約 75MB | 日本語はかなり不安定 |
| `ggml-base.bin` | 約 142MB | 軽量。要点は拾える |
| `ggml-small.bin` | 約 466MB | 実用の下限 |
| `ggml-large-v3-turbo.bin` | 約 1.6GB | 高精度・低速 |

---

## 生成される会議メモの例

```markdown
---
date: 2026-08-05
time: 10:30
duration: 45分
source: 20260805 103000.m4a
tags: [会議メモ]
---

# 2026-08-05 週次定例

## 概要

新機能のリリース時期と検証範囲について確認した。
リリースは翌週後半で合意し、検証の担当分担を決めた。

## 議題・論点

- **リリース時期** — 検証期間を確保するため前倒しは見送り
- **検証範囲** — 既存機能の回帰も含めるかで議論、含める方針に

## 決定事項

- リリースは翌週後半に実施
- 回帰テストを検証範囲に含める

## ToDo

- [ ] 検証項目表の作成（担当: 山田 / 期限: 金曜）
- [ ] リリース手順の確認

## 保留・次回確認

- 監視体制の担当（要確認）

---

## 文字起こし全文

...
```

---

## トラブルシューティング

まずログを確認してください。

```bash
tail -50 ~/.claude/logs/voice-memo-notes.log
```

### 「音声認識が許可されていません」と出る

1. `install.sh` を再実行して許可ダイアログで「OK」を選ぶ
2. または システム設定 → プライバシーとセキュリティ → **音声認識** で
   「ボイスメモ文字起こし」を有効にする

**ツールを再ビルドすると許可がリセットされます**（ad-hoc 署名のため）。
プラグイン更新後に失敗する場合はこれが原因です。

### 会議メモが作成されない

```bash
# launchd が登録されているか
launchctl list | grep voice-memo

# 手動実行して切り分ける
~/.claude/scripts/voice-memo-watch.sh
```

- 「文字起こしツールが見つかりません」→ `install.sh` を実行
- 「コマンドが見つかりません」（whisper エンジン）→ `install.sh` を実行
- 「短すぎるためスキップ」→ `source.min_seconds` を下げる
- ログに認証エラー → 上記「自動実行用トークンを設定」を実施

### 文字起こしが途中で切れている

`apple.chunk_seconds` が大きすぎる可能性があります。既定の 45 に戻してください。
60 を超えると末尾しか返らない挙動が出ます。

### 監視フォルダを変えたのに反応しない

launchd の監視先は plist に埋め込まれているため、登録し直しが必要です。

```bash
launchctl bootout gui/$(id -u)/com.user.voice-memo-notes
rm ~/Library/LaunchAgents/com.user.voice-memo-notes.plist
skills/voice-memo-notes/scripts/install.sh
```

### 同じ音声が何度も処理される / されない

処理済み記録は `~/.claude/state/voice-memo-processed.txt` です。

```bash
# 全件を再処理したい
rm ~/.claude/state/voice-memo-processed.txt

# 特定の1件だけ再処理したい（処理済み記録を無視して実行される）
~/.claude/scripts/voice-memo-transcribe.sh ~/path/to/audio.m4a
```

`min_seconds` で「短すぎる」と判定された録音も処理済みとして記録されます。
設定を下げてから再処理したい場合は、上記のとおり記録を消すか、ファイルを直接指定してください。

### プラグインを更新したら動かなくなった

`~/.claude/scripts/` のリンクが古いバージョンのフォルダを指しています。
`install.sh` を再実行するとリンクが張り直されます。

```bash
skills/voice-memo-notes/scripts/install.sh
```

### `Operation not permitted` と出る（voicememos モード）

フルディスクアクセスが未許可です。「パターンB」の手順を確認してください。
許可が難しい場合は `source.mode` を `export` に戻してください。

### 認識精度が低い / 一部しか文字起こしされない

- **まず録音品質を確認してください。** 32kbps 程度の低ビットレート録音では
  大半が欠落します（上記「録音品質の注意」を参照）。
  設定 → ボイスメモ → オーディオ品質 を「ロスレス」にしてください
- 固有名詞・専門用語が多い会議では `engine` を `whisper` に切り替える
- マイクから遠い・複数人が同時に話す録音は、どのエンジンでも精度が落ちます
- 生成された会議メモの要約には「（要確認）」が付く箇所があります。
  数値・金額・日付・固有名詞は必ず原文か記憶と照合してください

---

## 自動化を止める

```bash
launchctl bootout gui/$(id -u)/com.user.voice-memo-notes
rm ~/Library/LaunchAgents/com.user.voice-memo-notes.plist
```

Skill としての手動実行（`/voice-memo-notes`）は引き続き使えます。

文字起こしツール自体を消す場合:

```bash
rm -rf ~/.claude/state/VoiceMemoTranscriber.app
```

システム設定 → プライバシーとセキュリティ → 音声認識 からも項目を削除できます。
