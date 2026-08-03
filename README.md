# Productivity Suite for Claude Code

仕事の効率を向上させるスキル集。Gmail のメール対応自動化、タスク管理、カレンダー連携など、複数のプロダクティビティツールを統合したプラグインです。

**現在のスキル：**
- 📧 **Gmail Todo Manager** — Gmail のメール対応を自動で TODO.md に反映
- 🌅 **Morning Routine** — 今日の予定と進行中プロジェクトを TODO.md に書き出す
- 🎙️ **Voice Memo Notes** — ボイスメモの録音をローカル文字起こしし、要約付きの会議メモを自動作成

**今後追加予定：**
- ⏰ Task Manager — タスク管理とタイムトラッキング
- 📅 Calendar Sync — カレンダー統合
- その他生産性向上ツール

---

## クイックスタート

### 1. マーケットプレイスを追加

Claude Code で以下を実行：

```bash
/plugin marketplace add sup-mkajiwara/productivity-suite
```

### 2. プラグインをインストール

```bash
/plugin install productivity-suite@sup-mkajiwara-tools
```

### 3. Gmail Todo の設定（初回のみ）

設定ファイルを作成：

```bash
cp skills/gmail-todo/gmail-todo-config.json.template .claude/config/gmail-todo-config.json
```

`.claude/config/gmail-todo-config.json` を編集してメールアドレスを設定：

```json
{
  "email": "your-email@example.com"
}
```

### 4. スキルを実行

```bash
/morning-routine
/gmail-todo
```

### 5. ボイスメモ文字起こしの設定（使う場合のみ）

初回だけセットアップスクリプトを実行します（whisper.cpp と ffmpeg を導入します）。

```bash
skills/voice-memo-notes/scripts/install.sh
```

以降はボイスメモを監視フォルダに書き出すだけで会議メモが自動作成されます。
手動実行は `/voice-memo-notes`。詳細は [ボイスメモ自動化ガイド](docs/VOICE_MEMO.md) を参照してください。

---

## 使い方（Voice Memo Notes）

1. Mac のボイスメモで会議を録音する
2. 録音を選んで **共有 → ファイルに保存** で監視フォルダ（既定 `~/Documents/VoiceMemoInbox`）へ書き出す
3. 自動で文字起こしされ、`Obsidian Vault/会議メモ` に Markdown が作成される

作成される会議メモには **概要・議題・決定事項・ToDo・文字起こし全文** が含まれます。
音声は外部に送信せず、すべてローカルで文字起こしします。

取り込み元フォルダ・出力先フォルダは
`~/.claude/config/voice-memo-config.json` で自由に変更できます。

---

## 使い方（Gmail Todo Manager）

### メール一覧を確認

実行すると、対応が必要なメールが番号付きリストで表示されます：

```
## 対応が必要なメール

> ↩️ 要返信 ／ ⭐ スター付き ／ 🏷️ ToDo ／ 📩 未読

1. ↩️ **差出人名** 件名 — 要約
2. ⭐ **差出人名** 件名 — 要約
```

### 返信案を生成

返信したいメールの番号を選択：

```
1番のメールに返信したいです
```

Claude Code が返信案を自動生成します。

### 対応不要なメールを除外

```
2番は対応不要です
```

次回実行時から自動的に除外されます。

---

## ドキュメント

- **[セットアップガイド](docs/SETUP.md)** — インストール手順とトラブルシューティング
- **[カスタマイズガイド](docs/CUSTOMIZE.md)** — メールアドレス、検索期間、除外ルール等の設定方法
- **[ボイスメモ自動化ガイド](docs/VOICE_MEMO.md)** — 文字起こしの設定、フォルダ変更、トラブルシューティング

---

## スキル機能詳細

### Gmail Todo Manager — 対応メールの分類

| 絵文字 | 分類 | 説明 |
|------|------|------|
| ↩️ | 要返信 | 返信が必要なメール（最新メッセージが相手からのもの） |
| ⭐ | スター付き | Gmail でスター（重要マーク）がついているメール |
| 🏷️ | ToDo | Gmail の ToDo ラベルがついているメール |
| 📩 | 未読 | 上記に当てはまらない未読メール |

### 自動更新

マーケットプレイスで自動更新を有効にしている場合：

- Claude Code 起動後 0～10 分で自動的に最新版をダウンロード
- ユーザーの設定は保持される
- スキル機能が自動的に最新に

---

## ライセンス

MIT License

---

## ライセンス

MIT License

---

## サポート

問題が発生した場合は、[セットアップガイド](docs/SETUP.md) のトラブルシューティングを参照してください。

