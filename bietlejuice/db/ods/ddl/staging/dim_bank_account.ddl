DROP TABLE staging.dim_bank_account;

CREATE TABLE staging.dim_bank_account (
  sk_bank_account BIGINT NOT NULL,
  id_bank_account BIGINT,
  account_number VARCHAR(255),
  account_type VARCHAR(255),
  agency_number VARCHAR(255),
  ts_updated TIMESTAMP,
  ts_created TIMESTAMP,
  ts_load TIMESTAMP
)
WITH (oids = false);
