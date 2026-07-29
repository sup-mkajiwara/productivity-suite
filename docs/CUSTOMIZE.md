# カスタマイズガイド

## 設定ファイルの編集

`.claude/config/gmail-todo-config.json` を編集することで、スキルの動作をカスタマイズできます。

---

## メールアドレスの変更

```json
{
  "email": "your-new-email@example.com"
}
```

---

## 検索期間のカスタマイズ

### 未読メールの検索期間を変更

```json
{
  "search": {
    "unread_days": 7  // デフォルト: 1日 → 7日に変更
  }
}
```

### スター付きメールの検索期間を変更

```json
{
  "search": {
    "starred_days": 14  // デフォルト: 7日 → 14日に変更
  }
}
```

### 要返信候補の検索期間を変更

```json
{
  "search": {
    "reply_candidate_days": 30  // デフォルト: 14日 → 30日に変更
  }
}
```

---

## 除外メールの設定

### 特定の差出人を除外

```json
{
  "exclude": {
    "senders": [
      "marketing@company.com",
      "newsletter@news.jp"
    ]
  }
}
```

### 件名に特定のキーワードを含むメールを除外

```json
{
  "exclude": {
    "subjects": [
      "プロモーション",
      "割引",
      "お知らせ"
    ]
  }
}
```

### 本文に特定のキーワードを含むメールを除外

```json
{
  "exclude": {
    "keywords": [
      "Unsubscribe",
      "登録解除"
    ]
  }
}
```

---

## 出力先のカスタマイズ

### TODO.md のセクション名を変更

デフォルト: `メール対応（Gmail）`

```json
{
  "output": {
    "todo_section": "🔴 メール処理待ち"
  }
}
```

### メール一覧ファイルの保存先を変更

```json
{
  "output": {
    "list_file": "./docs/gmail-todo-list.md"
  }
}
```

---

## 完全な設定例

```json
{
  "email": "user@example.com",
  "search": {
    "unread_days": 1,
    "starred_days": 7,
    "todo_days": 7,
    "reply_candidate_days": 14
  },
  "exclude": {
    "senders": [
      "marketing@company.com",
      "newsletter@news.jp"
    ],
    "subjects": [
      "プロモーション",
      "割引"
    ],
    "keywords": [
      "Unsubscribe"
    ]
  },
  "output": {
    "list_file": ".claude/works/gmail-todo-list.md",
    "exclude_file": ".claude/works/gmail-todo-exclude.md",
    "todo_md": "TODO.md",
    "todo_section": "メール対応（Gmail）"
  }
}
```

---

## 設定が反映されない場合

1. ファイルが JSON として正しいか確認してください（[JSONLint](https://jsonlint.com/) で検証）
2. Claude Code を再起動してください
3. `/gmail-todo` を再度実行してください

