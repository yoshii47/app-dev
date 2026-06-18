-- ============================================================
-- PostgreSQL Schema (Neon)
-- ============================================================

-- --------------------------------------------------------
-- ENUM TYPES
-- --------------------------------------------------------
CREATE TYPE billing_cycle_type AS ENUM ('monthly', 'yearly', 'custom');
CREATE TYPE usage_frequency_type AS ENUM ('this_month', '1m_ago', '2m_ago', '3m_ago_or_more');
CREATE TYPE usage_level_type AS ENUM ('strong', 'medium', 'weak');
CREATE TYPE notification_decision_type AS ENUM ('continue', 'cancel', 'defer_1month');
CREATE TYPE cancellation_difficulty_type AS ENUM ('easy', 'medium', 'hard');

-- --------------------------------------------------------
-- 1.users
--   ユーザ情報テーブル(認証)
-- --------------------------------------------------------
CREATE TABLE users (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email                   VARCHAR(255) NOT NULL UNIQUE,
    password_hash           VARCHAR(255) NOT NULL,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- --------------------------------------------------------
-- 1. profiles
--    ユーザー情報テーブル（認証はJWTで自前実装）
-- --------------------------------------------------------
CREATE TABLE profiles (
    id                      UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    display_name            VARCHAR(255),
    mode                    VARCHAR(20) NOT NULL DEFAULT 'individual'
                                CHECK (mode IN ('individual', 'household')),
    household_id            UUID,                           -- 世帯モード時に参照
    review_candidate_count  INT NOT NULL DEFAULT 3,         -- 見直し候補の表示件数
    review_score_threshold  INT NOT NULL DEFAULT 40,        -- 見直し候補のスコア閾値
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- --------------------------------------------------------
-- 2. households
--    世帯モード用グループ
-- --------------------------------------------------------
CREATE TABLE households (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(255) NOT NULL,
    owner_id    UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE profiles
    ADD CONSTRAINT fk_profiles_household
    FOREIGN KEY (household_id) REFERENCES households(id) ON DELETE SET NULL;

-- --------------------------------------------------------
-- 3. household_members
--    世帯メンバー（owner_id 以外のメンバー管理）
-- --------------------------------------------------------
CREATE TABLE household_members (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id    UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (household_id, user_id)
);

-- --------------------------------------------------------
-- 4. categories
--    サブスクのカテゴリ（動画・音楽・生産性ツール等）
-- --------------------------------------------------------
CREATE TABLE categories (
    id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name    VARCHAR(100) NOT NULL UNIQUE
);

-- --------------------------------------------------------
-- 5. master_services
--    大手サービスのマスタ（Netflix, Spotify 等）
--    値上げ通知・解約手順案内の対象
-- --------------------------------------------------------
CREATE TABLE master_services (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                    VARCHAR(255) NOT NULL UNIQUE,
    category_id             UUID REFERENCES categories(id) ON DELETE SET NULL,
    logo_url                TEXT,
    cancellation_url        TEXT,                           -- 解約ページURL
    cancellation_difficulty cancellation_difficulty_type,
    cancellation_steps      TEXT,                          -- 解約手順（Markdown可）
    current_monthly_price   DECIMAL(10, 2),                -- 現在の月額（参考値）
    current_yearly_price    DECIMAL(10, 2),                -- 現在の年額（参考値）
    currency                VARCHAR(3) NOT NULL DEFAULT 'JPY',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- --------------------------------------------------------
-- 6. service_price_changes
--    大手サービスの値上げ履歴（静的DB）
-- --------------------------------------------------------
CREATE TABLE service_price_changes (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    master_service_id   UUID NOT NULL REFERENCES master_services(id) ON DELETE CASCADE,
    changed_at          DATE NOT NULL,
    old_price           DECIMAL(10, 2),
    new_price           DECIMAL(10, 2),
    currency            VARCHAR(3) NOT NULL DEFAULT 'JPY',
    billing_cycle       billing_cycle_type NOT NULL,
    note                TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- --------------------------------------------------------
-- 7. subscriptions
--    ユーザーが登録したサブスク情報
-- --------------------------------------------------------
CREATE TABLE subscriptions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    household_id        UUID REFERENCES households(id) ON DELETE SET NULL, -- 世帯共有時
    master_service_id   UUID REFERENCES master_services(id) ON DELETE SET NULL,
    category_id         UUID REFERENCES categories(id) ON DELETE SET NULL,
    service_name        VARCHAR(255) NOT NULL,
    billing_cycle       billing_cycle_type NOT NULL,
    custom_cycle_days   INT,                        -- billing_cycle='custom' 時のみ
    custom_cycle_text   VARCHAR(100),               -- 表示用ラベル
    start_date          DATE NOT NULL,
    next_billing_date   DATE NOT NULL,
    continuation_level  VARCHAR(20)
                            CHECK (continuation_level IN ('definitely', 'probably', 'unsure', 'probably_not', 'cancel')),
    notify_enabled      BOOLEAN NOT NULL DEFAULT TRUE,
    is_archived         BOOLEAN NOT NULL DEFAULT FALSE,
    archived_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- --------------------------------------------------------
-- 8. subscription_prices
--    サブスクの料金履歴（値上げ等で変動する可能性を考慮）
-- --------------------------------------------------------
CREATE TABLE subscription_prices (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id     UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    amount              DECIMAL(10, 2) NOT NULL,
    currency            VARCHAR(3) NOT NULL DEFAULT 'JPY',
    jpy_amount          DECIMAL(10, 2),             -- JPY換算額
    exchange_rate       DECIMAL(10, 6),
    exchange_rate_date  DATE,
    effective_from      DATE NOT NULL,
    effective_to        DATE,                        -- NULL = 現在有効
    reason              VARCHAR(100),               -- 変更理由（値上げ等）
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- --------------------------------------------------------
-- 9. exchange_rates
--    通貨の為替レート（日次）
-- --------------------------------------------------------
CREATE TABLE exchange_rates (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    currency    VARCHAR(3) NOT NULL,
    rate        DECIMAL(10, 6) NOT NULL,           -- 1 currency = rate JPY
    rate_date   DATE NOT NULL,
    UNIQUE (currency, rate_date)
);

-- --------------------------------------------------------
-- 10. check_ins
--     チェックイン回答記録
-- --------------------------------------------------------
CREATE TABLE check_ins (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id     UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    user_id             UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    checked_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    usage_frequency     usage_frequency_type NOT NULL,
    usage_level         usage_level_type NOT NULL
);

-- --------------------------------------------------------
-- 11. cost_scores
--     コスパスコアの月次記録
-- --------------------------------------------------------
CREATE TABLE cost_scores (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    year_month      CHAR(7) NOT NULL,              -- "YYYY-MM" 形式
    score           INT NOT NULL CHECK (score BETWEEN 0 AND 100),
    ai_comment      TEXT,                          -- Gemini生成コメント（30字以内）
    calculated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (subscription_id, year_month)
);

-- --------------------------------------------------------
-- 12. notification_logs
--     送信済み通知の記録
-- --------------------------------------------------------
CREATE TABLE notification_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id     UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    user_id             UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    notified_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    notification_type   VARCHAR(50) NOT NULL,      -- 'renewal_7d', 'renewal_1d', 'checkin', 'price_change' 等
    email_to            VARCHAR(255) NOT NULL
);

-- --------------------------------------------------------
-- 13. notification_tokens
--     メール内アクションリンク用ワンタイムトークン
--     「継続する」「解約する」「1ヶ月保留」の3択対応
-- --------------------------------------------------------
CREATE TABLE notification_tokens (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    token           VARCHAR(255) NOT NULL UNIQUE,
    decision        notification_decision_type,    -- 使用後に記録
    expires_at      TIMESTAMPTZ NOT NULL,
    used_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);



-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX idx_subscriptions_user_id         ON subscriptions(user_id);
CREATE INDEX idx_subscriptions_next_billing    ON subscriptions(next_billing_date) WHERE is_archived = FALSE;
CREATE INDEX idx_subscription_prices_sub_id    ON subscription_prices(subscription_id);
CREATE INDEX idx_check_ins_subscription_id     ON check_ins(subscription_id);
CREATE INDEX idx_cost_scores_sub_year_month    ON cost_scores(subscription_id, year_month);
CREATE INDEX idx_notification_tokens_token     ON notification_tokens(token);
CREATE INDEX idx_exchange_rates_currency_date  ON exchange_rates(currency, rate_date);
