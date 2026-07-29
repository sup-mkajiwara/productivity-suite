# セットアップガイド

## インストール手順

### 1. マーケットプレイスを追加

Claude Code で以下を実行：

```
/plugin marketplace add sup-mkajiwara/productivity-suite
```

### 2. プラグインをインストール

```
/plugin install gmail-todo@sup-mkajiwara-tools
```

### 3. 設定ファイルを作成

テンプレートをコピーして `.claude/config/gmail-todo-config.json` を作成：

```bash
cp skills/gmail-todo/gmail-todo-config.json.template .claude/config/gmail-todo-config.json
```

### 4. メールアドレスをカスタマイズ

`.claude/config/gmail-todo-config.json` を編集：

```json
{
  "email": "your-email@example.com"
  // その他の設定...
}
```

### 5. スキルを実行

```
/gmail-todo
```

---

## 自動更新の確認

プラグインの自動更新を有効にしている場合、起動後 0～10 分で自動的に最新版をダウンロードします。

手動で更新チェックしたい場合：

```
/plugin update
```

---

## 必須設定

| 項目 | 説明 |
|------|------|
| `email` | Gmail のメールアドレス（to:xxx の対象） |

## オプション設定

| 項目 | デフォルト | 説明 |
|------|----------|------|
| `unread_days` | 1 | 未読メールの検索期間（日） |
| `starred_days` | 7 | スター付きメールの検索期間（日） |
| `todo_days` | 7 | ToDo ラベル付きメールの検索期間（日） |
| `reply_candidate_days` | 14 | 要返信候補の検索期間（日） |

---

## トラブルシューティング

### Gmail コネクタが未承認

```
Gmail コネクタが未承認のため取得をスキップしました
```

**解決方法：**
- Claude Code の設定から Gmail コネクタを承認してください
- `/plugin` → Gmail → 認証を試してください

### メールが取得されない

- メールアドレスが正しいか確認してください
- 検索期間を長くしてみてください（`reply_candidate_days` を 30 に）
- Gmail 検索フィルタが正しいか確認してください

