# Productivity Suite for Claude Code

仕事の効率を向上させるスキル集。Gmail のメール対応自動化、タスク管理、カレンダー連携など、複数のプロダクティビティツールを統合したプラグインです。

**現在のスキル：**
- 📧 **Gmail Todo Manager** — Gmail のメール対応を自動で TODO.md に反映

**今後追加予定：**
- ⏰ Task Manager — タスク管理とタイムトラッキング
- 📅 Calendar Sync — カレンダー統合
- その他生産性向上ツール

---

## セットアップ

### 前提条件

- GitHub アカウント（このプライベートリポジトリへのアクセス権限が必要）
- SSH キーまたは GitHub CLI で認証済み

### 1. プロジェクトで `.claude/settings.json` を作成

プロジェクトのルートの `.claude/settings.json` に以下を追加：

```json
{
  "extraKnownMarketplaces": {
    "productivity-suite": {
      "source": {
        "source": "github",
        "repo": "sup-mkajiwara/productivity-suite"
      }
    }
  },
  "enabledPlugins": {
    "productivity-suite@sup-mkajiwara": true
  }
}
```

または、このリポジトリのテンプレートをコピー：

```bash
cp .claude/settings.json.template /path/to/your/project/.claude/settings.json
```

### 2. Gmail Todo の設定ファイルを作成

```bash
cp skills/gmail-todo/gmail-todo-config.json.template .claude/config/gmail-todo-config.json
```

メールアドレスを編集：

```json
{
  "email": "your-email@example.com"
}
```

### 3. Claude Code を再起動

`.claude/settings.json` が自動的に読み込まれ、マーケットプレイスが登録されます。

### 4. スキルを実行

```
/morning-routine
/gmail-todo
```

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

## プライベート配布

このプラグインは **GitHub のプライベートリポジトリ** で管理されています。

利用するには：
- GitHub アカウントが必要
- 本リポジトリへのアクセス権限が必要
- プロジェクトの `.claude/settings.json` で `extraKnownMarketplaces` を登録

---

## ライセンス

MIT License

---

## サポート

問題が発生した場合は、[セットアップガイド](docs/SETUP.md) のトラブルシューティングを参照してください。

