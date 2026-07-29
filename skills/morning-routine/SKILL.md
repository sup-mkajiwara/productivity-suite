---
description: 今日のスケジュール(GoogleCalendar)と進行中プロジェクトを TODO.md に書き出す朝のルーティン
---

# 朝のルーティン（Morning Routine）

毎朝実行するルーティンです。Google Calendar のスケジュールと進行中プロジェクトを Obsidian Vault の `TODO.md` に自動更新します。

## 実行方法

```
/morning-routine
```

または launchd で定時実行可能です。

---

## 実行内容

### 1. 今日のスケジュールを取得

- **このメッセージ内に「本日の予定（gcalcli の TSV 出力）」が渡されている場合は、それを使う**（ツール実行は不要）
  - launchd 経由の朝ルーティンでは、シェル側で `gcalcli agenda --tsv` を実行した結果がここに貼られます
- 渡されていない場合（手動実行など）は、Bash で自分で取得します：
  ```bash
  gcalcli agenda --tsv "$(date +%Y-%m-%d)" "$(date -v+1d +%Y-%m-%d)"
  ```
- TSV は1行目がヘッダー `start_date  start_time  end_date  end_time  title`、2行目以降が予定
- 各予定は `start_time`-`end_time` と `title` から `HH:MM-HH:MM タイトル` の形式で整形します
- ※ Claude Code の Google Calendar MCP は launchd 等のヘッドレス実行では使えないため、必ず gcalcli / 渡された TSV を使用します

### 2. プロジェクトを取得

- Obsidian Vault 内の **進行中プロジェクト**を一覧化
- Obsidian Vault 内の **商談中プロジェクト**を一覧化
- 拡張子 `.md` は除去し、Obsidian 内部リンク `[[名前]]` 形式に変換します

### 3. Gmail の対応 ToDo を取得（オプション）

- Claude Code で手動実行している場合、Gmail コネクタが利用可能なら実行
- 以下を分類して取得：
  - ↩️ **要返信** — 返信が必要なメール
  - ⭐ **スター付き** — 重要なマーク済みメール
  - 🏷️ **ToDo** — Gmail の ToDo ラベルが付いているメール
  - 📩 **未読** — 上記に当てはまらない未読メール
- 優先度順（↩️ → ⭐ → 🏷️ → 📩）に並べます

**注:** launchd 等の非対話実行やコネクタ未承認の場合は Gmail 取得をスキップします（エラーにはなりません）

### 4. TODO.md を自動更新

TODO.md に以下の順で追加・更新：

```markdown
## YYYY-MM-DD(曜) スケジュール
- 10:00-11:00 朝礼
- 14:00-15:00 会議

## 進行中プロジェクト
- [[プロジェクトA]]
- [[プロジェクトB]]

## 商談中プロジェクト
- [[プロジェクトC]]

## メール対応（Gmail）
> ↩️ 要返信 ／ ⭐ スター付き ／ 🏷️ ToDo ／ 📩 未読

- ↩️ **差出人名** 件名 — 要約
- ⭐ **差出人名** 件名 — 要約
- 🏷️ **差出人名** 件名 — 要約

## タスク
> 🔵 今日やる ／ 🟡 連絡が来たら対応 ／ 🟢 できたら対応 ／ ⚪ 今日はやらない

- 🔵 タスク内容...
```

**重要：**
- 既に当日のセクションがある場合は、その内容だけを上書きします
- `## タスク` セクションは **表示のみで内容は更新しません**（手動で絵文字を記入してください）
- `## 相談すること` など他のセクションはそのまま残します
- 当日分だけを更新し、他の日付や既存データは変更しません

---

## プロジェクトフォルダについて

Obsidian Vault 内に以下のフォルダ構造が必要です：

```
プロジェクト/
├── 進行中/           # 進行中プロジェクト（.md ファイル）
├── 商談中/           # 商談中プロジェクト（.md ファイル）
└── ペンディング/      # 保留中のプロジェクト
```

**フォルダが存在しない場合は自動作成されます。**

プロジェクトのファイル名が `[[プロジェクト名]]` としてリンク化されるため、Obsidian 内でクリックして詳細を確認できます。

---

## 連携スキル

**Gmail Todo Manager**と組み合わせることで、より詳細なメール対応が可能です：

```
/morning-routine        # 朝のスケジュール + 簡易メール一覧 + ToDo ラベル対応
/gmail-todo             # メール詳細の確認・返信案生成
```

---

## launchd での定時実行

毎朝 6:00 に自動実行する設定例：

```bash
# ~/Library/LaunchAgents/com.user.morning-routine.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.morning-routine</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>cd /path/to/your/project && /usr/local/bin/gcalcli agenda --tsv "$(date +%Y-%m-%d)" "$(date -v+1d +%Y-%m-%d)" | claude /morning-routine</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>6</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
</dict>
</plist>
```

---

## 注意事項

- 予定に含まれる取引先名・担当者名などは社外に転記しないよう注意してください
- 予定が0件の場合は「本日の予定はありません」と記載します
- TODO.md のパスは Obsidian Vault 内の `TODO.md` を対象とします
- 既存コンテンツを上書きしないよう、当日のセクションのみを差し替えます
