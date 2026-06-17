# Subscription App DB設計要件書

**プロジェクト名：** サブスク管理アプリ  
**作成日：** 2026-06-03  
**フェーズ：** DB設計（スキーマ定義前）

---

## 1. 概要

サブスクリプションを一元管理し、解約・継続の意思決定を補助するWebアプリケーション。  
使用技術：PostgreSQL（Neon）、Next.js、Express、Gemini API、Resend

**重要な設計方針：**
- すべてのテーブルのPKは **UUID** で統一
- 計算可能なデータは別テーブルに持たない（正規化原則）
- 為替変動に対応：毎営業日レート自動取得、土日祝は直前値参照
- 料金変更履歴を完全に追跡可能にする設計

---

## 2. テーブル一覧（11個）

### 2.1 コアテーブル（3個）

#### users
ユーザー基本情報
```
- id: UUID (PK)
- email: VARCHAR(255) (UNIQUE)
- mode: VARCHAR(50) → "personal" or "household"
- created_at: TIMESTAMP
- updated_at: TIMESTAMP
```

#### subscriptions
ユーザーが登録したサブスク
```
- id: UUID (PK)
- user_id: UUID (FK → users.id)
- master_service_id: UUID (FK → master_services.id, NULL可)
- service_name: VARCHAR(255)
- billing_cycle: ENUM('monthly', 'yearly', 'custom')
- custom_cycle_days: INT (custom の場合のみ有効)
- custom_cycle_text: VARCHAR(100) (例："30日固定", "2週間トライアル")
- start_date: DATE
- next_billing_date: DATE (node-cronで毎日更新)
- continuation_level: VARCHAR(50) (ユーザー入力の継続予定度)
- is_archived: BOOLEAN (DEFAULT: false)
- created_at: TIMESTAMP
```

**重要：** 料金はこのテーブルに持たず、subscription_prices テーブルに分離

#### master_services
定型サービスのマスタデータ（Netflix、Amazon Prime等）
```
- id: UUID (PK)
- name: VARCHAR(255) (例："Netflix", "Amazon Prime")
- default_usd_price: DECIMAL(10, 2) (公式価格、USD建て)
- category: VARCHAR(100) (例："Entertainment", "Music")
- official_url: VARCHAR(500)
- created_at: TIMESTAMP
```

---

### 2.2 価格・為替管理テーブル（2個）

#### subscription_prices
サブスク料金の履歴（価格変更を完全追跡）
```
- id: UUID (PK)
- subscription_id: UUID (FK → subscriptions.id)
- original_price: DECIMAL(10, 2) (元の価格、例：$9.99)
- original_currency: VARCHAR(3) (JPY, USD, EUR等)
- jpy_price: DECIMAL(10, 2) (日本円に換算した金額)
- exchange_rate: DECIMAL(10, 6) (使用した為替レート)
- exchange_rate_date: DATE (どの日のレートを使ったか)
- effective_from: DATE (この料金が有効になった日)
- effective_to: DATE (この料金が終了した日, NULL=現在有効)
- reason: VARCHAR(50) (例："new", "price_hike", "fx_change")
- created_at: TIMESTAMP
```

**重要：** 
- $サブスク登録時：その日のレート × $価格 = JPY金額を計算して保存
- 料金変更時：新しい行を追加（更新ではなく挿入）
- 過去の支払い予測を正確に再現可能にする設計

#### exchange_rates
為替レート履歴（毎営業日自動取得）
```
- id: UUID (PK)
- currency: VARCHAR(3) (USD, EUR等)
- rate: DECIMAL(10, 6) (例：1USD = 150.123456 JPY)
- date: DATE (UNIQUE per currency+date)
- source: VARCHAR(50) (例："Yahoo Finance API")
- is_official: BOOLEAN (true=営業日の公式, false=直前営業日の値)
- fetched_at: TIMESTAMP
```

**運用ルール：**
- 毎営業日14時に自動取得（node-cron）
- 土日祝は直前営業日のレートを is_official=false で参照
- Yahoo Finance API を使用

---

### 2.3 チェックイン・スコアテーブル（2個）

#### check_ins
定期的なチェックイン記録（隔週送信、ユーザーが「使ってるか」を回答）
```
- id: UUID (PK)
- subscription_id: UUID (FK → subscriptions.id)
- checked_date: DATE (チェック日)
- usage_frequency: VARCHAR(50) (例："this-month", "1m-ago", "2m-ago", "not-used")
- usage_level: VARCHAR(50) (例："strong", "medium", "weak")
- created_at: TIMESTAMP
```

**仕様：**
- 隔週でメール送信
- 最大3件まで一度に送信
- 優先度キュー：スコアが低いもの・未チェック期間が長いものを優先

#### usage_value_scores
月次のコスパスコア記録（コスパ値の推移）
```
- id: UUID (PK)
- subscription_id: UUID (FK → subscriptions.id)
- year_month: VARCHAR(7) (例："2026-06", ユニークキーの一部)
- score: INT (0～100)
- ai_comment: VARCHAR(30) (Gemini APIで生成, スコア低い場合のみ)
- usage_frequency: VARCHAR(50) (記録用：この月の使用頻度)
- usage_level: VARCHAR(50) (記録用：この月の使用レベル)
- continuation_level: VARCHAR(50) (記録用：継続予定度)
- monthly_price: DECIMAL(10, 2) (記録用：この月の料金)
- calculated_at: TIMESTAMP
- UNIQUE(subscription_id, year_month)
```

**スコア計算要素（バックエンドで実装）：**
- 使用頻度（check_ins.usage_frequency）
- 使用レベル（check_ins.usage_level）
- 継続予定レベル（subscriptions.continuation_level）
- 金額（subscription_prices.jpy_price）
- 継続期間（subscriptions.start_dateから計算）

**アルゴリズムは DB設計段階では定義しない。バックエンド実装時に決定。**

---

### 2.4 通知・設定テーブル（2個）

#### notification_settings
サブスクごとの通知設定
```
- id: UUID (PK)
- subscription_id: UUID (FK → subscriptions.id, UNIQUE)
- is_enabled: BOOLEAN (DEFAULT: true)
- created_at: TIMESTAMP
- updated_at: TIMESTAMP
```

#### notifications
送信済み通知のログ（監査・復帰用）
```
- id: UUID (PK)
- subscription_id: UUID (FK → subscriptions.id)
- type: VARCHAR(50) (例："update-reminder", "checkin-prompt", "value-alert")
- sent_at: TIMESTAMP
- status: VARCHAR(50) (例："sent", "opened", "clicked")
- created_at: TIMESTAMP
```

---

### 2.5 マスタデータテーブル（2個）

#### master_price_hikes
主要サービスの値上げ情報
```
- id: UUID (PK)
- master_service_id: UUID (FK → master_services.id)
- old_price: DECIMAL(10, 2)
- new_price: DECIMAL(10, 2)
- effective_date: DATE (値上げ実施日)
- created_at: TIMESTAMP
```

#### master_cancellation_guides
主要サービスの解約手順ガイド
```
- id: UUID (PK)
- master_service_id: UUID (FK → master_services.id)
- cancellation_url: VARCHAR(500) (解約ページへのURL)
- difficulty: VARCHAR(50) (例："easy", "medium", "hard")
- steps: TEXT (ステップバイステップガイド)
- created_at: TIMESTAMP
```

---

## 3. リレーション図

```
users
  ├─ 1 → N subscriptions
  ├─ 1 → N notifications
  └─ 1 → N notification_settings

subscriptions
  ├─ N → 1 users
  ├─ N → 1 master_services
  ├─ 1 → N subscription_prices
  ├─ 1 → N check_ins
  ├─ 1 → N usage_value_scores
  └─ 1 → 1 notification_settings

master_services
  ├─ 1 → N subscriptions
  ├─ 1 → N master_price_hikes
  └─ 1 → N master_cancellation_guides

subscription_prices
  └─ N → 1 exchange_rates (via exchange_rate_date)

exchange_rates
  └─ 1 → N subscription_prices

check_ins
  └─ N → 1 subscriptions

usage_value_scores
  └─ N → 1 subscriptions

notification_settings
  └─ 1 → 1 subscriptions

notifications
  └─ N → 1 subscriptions
```

---

## 4. 設計上の重要なポイント

### 4.1 為替管理の仕様

**対象：** USD、EUR等の$表記サブスク

**処理フロー：**
1. ユーザーが「Apple Music」（$10.99）を登録
2. その日の exchange_rates から USD/JPY レートを取得
3. $10.99 × 150.50 = ¥1,654円として subscription_prices に保存
4. 翌日レート変動 → 新しい行が追加される（上書きではなく）

**エッジケース対応：**
- 土日祝：直前営業日のレートを使用（is_official=false で記録）
- 31日契約が2月に来た場合：`next_billing_date` は28日に繰り上げ（バックエンドで制御）

### 4.2 料金変更の追跡

subscription テーブルに price カラムを持たない理由：
- 支払い額の履歴が失われる
- 「昨年同月はいくら払ってたか」が不明になる

**正しいアプローチ：**
```
subscription_prices は INSERT のみ（UPDATE しない）
→ 過去の支払い予測を常に正確に再現可能
```

### 4.3 スコア計算の責務分離

**DB設計段階（ここ）：**
- どのデータを保存するか（テーブル構造）

**バックエンド実装段階（後）：**
- スコア算出アルゴリズム
- Gemini API連携
- node-cron での自動計算タイミング

スキーマ設計時は「何を保存するか」に集中。「どう計算するか」は考えない。

### 4.4 定型 vs カスタムの切り分け

```
master_service_id が NULL
  → カスタム入力（ユーザーが service_name を入力）
  
master_service_id が有効
  → 定型サービス（master_services.name を参照）
  → 値上げ通知・解約ガイドが活用可能
```

### 4.5 billing_cycle の扱い

```
ENUM('monthly', 'yearly', 'custom')

custom の場合：
  - custom_cycle_days に日数を記録（30, 14等）
  - custom_cycle_text に説明を記録（"30日固定", "2週間トライアル"等）
  - next_billing_date を node-cron で毎日更新
```

---

## 5. 主キー戦略

**すべてのテーブルで UUID を主キーに統一**

理由：
- グローバルに一意（分散DB対応）
- セキュアで可読性が高い
- PostgreSQL標準の `gen_random_uuid()`（pg13+）

---

## 6. インデックス設計（Phase 2以降）

現段階では定義しない。スキーマ実装後、クエリパフォーマンス測定時に追加。

想定されるインデックス候補：
- `subscriptions(user_id)`
- `subscription_prices(subscription_id, effective_from)`
- `exchange_rates(currency, date)`
- `check_ins(subscription_id, checked_date)`
- `usage_value_scores(subscription_id, year_month)`

---

## 7. 制約一覧

| 制約 | 対象 | 理由 |
|------|------|------|
| PK: UUID | すべてのテーブル | テーブル識別 |
| FK | 外部キー参照 | リレーション保証 |
| UNIQUE | users.email | ユーザー一意性 |
| UNIQUE | exchange_rates(currency, date) | 同じ日付のレート重複防止 |
| UNIQUE | usage_value_scores(subscription_id, year_month) | 月一度のスコア保証 |
| NOT NULL | 重要カラム | データ品質保証 |
| ENUM | billing_cycle 等 | 選択肢制限 |
| CHECK | score (0-100) | スコア範囲保証（実装時） |

---

## 8. データベースエンジン

**PostgreSQL（Neon / サーバーレス）**

使用する PostgreSQL 固有機能：
- UUID 型 + gen_random_uuid()
- ENUM 型
- TIMESTAMPTZ サポート

※ 定期実行は DB の pg_cron ではなく、アプリ層の node-cron で行う。

---

## 9. 次のステップ

1. **Figmaで ER図を描画** ← 今ここ
   - テーブル、カラム、リレーション を可視化
   
2. **このドキュメントをレビュー**
   - チーム内で仕様確認
   - 抜け漏れチェック

3. **SQL スキーマ実装**
   - CREATE TABLE 文を全て記述
   - Neon に適用（Phase1〜2はpgで直接、Phase3以降はPrisma Migrate）

4. **バックエンド処理実装**
   - アルゴリズム
   - API連携
   - node-cron ジョブ

---

## 補足：設計時のポイント

### 正規化原則
```
❌ 月額・年額・平均年額をテーブルに持つ
✅ subscription_prices から都度計算する
```

### 監査可能性
```
✅ すべての料金変更を subscription_prices で履歴管理
✅ すべてのレート変動を exchange_rates で履歴管理
✅ スコア計算に使った値を usage_value_scores に保記録
```

### スケーラビリティ
```
✅ ユーザー数増加に対応（user_id の FK構造）
✅ サブスク数増加に対応（subscription_id の FK構造）
✅ 各テーブルで created_at を持つ（監査・分析用）
```

---

**作成者：Claude**  
**最終更新：2026-06-03**
