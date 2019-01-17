DROP TABLE staging.fact_bank_transaction;

CREATE TABLE staging.fact_bank_transaction (
  sk_bank_transaction BIGINT NOT NULL,
  id_bank_transaction BIGINT,
  ts_trasaction TIMESTAMP,
  value NUMERIC(22,2),
  sk_bank_account INTEGER,
  house_id BIGINT,
  sk_user BIGINT,
  sk_bank INTEGER,
  ts_load TIMESTAMP
)
WITH (oids = false);
