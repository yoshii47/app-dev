# CLAUDE.md

このファイルはClaude Code（CLI・VS Code拡張）がプロジェクトを理解するための概要です。

---

## アプリ概要

**サブスク管理アプリ** — サブスクを惰性ではなく選択にする。

契約中のサブスクリプションを一元管理し、解約忘れ防止・コスパ見直し促進・意思決定補助を行うWebアプリ。

---

## 技術スタック

| 領域 | 技術 |
|---|---|
| フロントエンド | Next.js (React) + Tailwind CSS |
| バックエンド | Node.js + Express / Hono |
| DB | PostgreSQL (自前構成) |
| ORM | Prisma |
| 認証 | JWT |
| 定期処理 | node-cron |
| メール通知 | Resend |
| AI | Gemini API |
| ホスティング | Vercel |

---

## ディレクトリ構成

```
site_praciting/
├── .gitignore
├── package.json             # ルート（npm workspaces）
├── docs/
│   ├── CLAUDE.md
│   ├── 要件定義書.md        # 機能・非機能要件の全詳細
│   ├── schema.sql           # DBスキーマ（PostgreSQL）
│   └── DBERfigure.png       # ER図
└── src/
    ├── frontend/            # Next.jsアプリ
    └── backend/             # Express / Hono API
```

---

## 主要機能（Phase1 MVP）

1. **サブスク登録** — 手入力 / 自然言語（Gemini API）
2. **更新通知** — 更新日の事前メール通知（monthly: 1週間前・1日前 / yearly: 1ヶ月前・1週間前・1日前）。メール内に「継続する」「解約する」「1ヶ月保留」の3択ボタン付き
3. **チェックイン** — 隔週メールで使用頻度・使用レベルを回答（カード形式UI、最大3件/回）
4. **コスパスコア** — 使用頻度・継続期間・金額・継続予定レベルからアルゴリズムで0〜100点を算出。月次で推移グラフ表示
5. **見直し候補** — スコアが低いサブスクをピックアップ。累計支払額・今後の支払予測を表示
6. **可視化** — 月額・年額合計、カテゴリ別グラフ、スコア推移（折れ線グラフ）

---

## DBスキーマ概要

主要テーブルと役割：

| テーブル | 役割 |
|---|---|
| `profiles` | Supabase Auth拡張。個人/世帯モード、見直し設定を保持 |
| `households` / `household_members` | 世帯モードのグループ管理 |
| `subscriptions` | サブスク登録情報（課金サイクル・次回請求日・継続予定レベル等） |
| `subscription_prices` | 料金履歴（値上げ対応、外貨換算含む） |
| `master_services` | 大手サービスのマスタ（解約URL・解約難易度・解約手順） |
| `service_price_changes` | 大手サービスの値上げ履歴（静的DB） |
| `check_ins` | チェックイン回答記録 |
| `cost_scores` | コスパスコアの月次記録 + AIコメント |
| `notification_logs` | 送信済み通知の記録 |
| `notification_tokens` | メール内3択ボタン用ワンタイムトークン |
| `exchange_rates` | 為替レート（日次） |
| `categories` | サブスクカテゴリ |

---

## 認証

- JWT（JSON Web Token）によるメール認証
- アクセス制御はアプリケーション層で実装

---

## 開発フェーズ

- **Phase1（現在）**: Web app MVP
- **Phase2**: PWA化・プッシュ通知・スクショOCR登録
- **Phase3**: iOS / Androidネイティブアプリ

---

## 詳細ドキュメント

機能要件・非機能要件の詳細は [docs/要件定義書.md](docs/要件定義書.md) を参照。
