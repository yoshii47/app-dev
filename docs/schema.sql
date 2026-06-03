CREATE table User (
    id int primary key,
    name varchar(255) not null,
    email varchar(255) not null unique,
    mode BOOLEAN not null default false,
    created_at datetime not null default current_timestamp,  
    updated_at datetime not null default current_timestamp on update current_timestamp
);

CREATE TABLE subscriptions (
  id UUID PRIMARY KEY,                          -- 特殊型
  user_id UUID NOT NULL,                        -- 特殊型
  master_service_id UUID,                       -- 特殊型（NULL可）
  service_name VARCHAR(255) NOT NULL,           -- 文字列
  billing_cycle ENUM('monthly', 'yearly', 'custom'), -- 特殊型
  custom_cycle_days INT,                        -- 数値
  custom_cycle_text VARCHAR(100),               -- 文字列
  start_date DATE NOT NULL,                     -- 日付
  next_billing_date DATE NOT NULL,              -- 日付
  is_archived BOOLEAN DEFAULT FALSE,            -- 論理
  continuation_level VARCHAR(50),               -- 文字列
  created_at TIMESTAMP DEFAULT now()            -- 日時
);

CREATE TABLE subscription_prices (
  id UUID PRIMARY KEY,
  subscription_id UUID NOT NULL,
  original_price DECIMAL(10, 2),                -- 金額
  original_currency VARCHAR(3),                 -- 文字列
  jpy_price DECIMAL(10, 2),                     -- 金額
  exchange_rate DECIMAL(10, 6),                 -- 為替
  exchange_rate_date DATE,
  effective_from DATE,
  effective_to DATE,
  reason VARCHAR(50),
  created_at TIMESTAMP
);


CREATE TABLE check_ins (
    id UUID PRIMARY KEY,
    subscription_id UUID,
    checked_date datetime,
    usage_frequency ENUM("this-month","1m-ago","2m-ago","3m-ago"),
    usage_level ENUM("strong","medium","weak"),
    created_at datetime default current_timestamp
);


CREATE TABLE usage_value_score(
    id UUID primary key,
    FOREIGN KEY (subscription_id) REFERENCES subscriptions(id),
    year_month varchar(7) not null, -- "YYYY-MM"形式
    score INT,
    ai_comment TEXT,
    calculated_at datetime default current_timestamp
);

CREATE TABLE exchange_rates(
    id UUID primary key,
    currency VARCHAR,
    rate DECIMAL(10, 6),
    date DATE unique,
)