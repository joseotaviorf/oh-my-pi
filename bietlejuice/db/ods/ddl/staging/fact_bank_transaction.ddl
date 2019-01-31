DROP TABLE staging.fact_bank_transaction;

CREATE TABLE staging.fact_bank_transaction (
  sk_bank_transaction BIGINT NOT NULL,
  ts_transaction TIMESTAMP,
  sk_transaction BIGINT,
  value NUMERIC(22,2),
  sk_bank_account INTEGER,
  id_house BIGINT,
  sk_user_recipient BIGINT,
  sk_bank INTEGER,
  type VARCHAR(255),
  ts_updated TIMESTAMP,
  ts_created TIMESTAMP,
  ts_load TIMESTAMP
)
WITH (oids = false);
