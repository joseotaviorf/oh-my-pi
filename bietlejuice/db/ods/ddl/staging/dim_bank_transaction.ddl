DROP TABLE staging.dim_bank_transaction;

CREATE TABLE staging.dim_bank_transaction (
  sk_bank_transaction BIGINT NOT NULL,
  id_bank_transaction BIGINT,
  description VARCHAR(255),
  type VARCHAR(255),
  updated_at TIMESTAMP,
  created_at TIMESTAMP,
  ts_load TIMESTAMP
)
WITH (oids = false);
