DROP TABLE staging.dim_bank;

CREATE TABLE staging.dim_bank (
  sk_bank BIGINT NOT NULL,
  id_bank BIGINT,
  updated_at TIMESTAMP,
  created_at TIMESTAMP,
  code VARCHAR(255),
  name VARCHAR(255),
  febraban_name VARCHAR(255),
  featured_rank INTEGER,
  ts_load TIMESTAMP
)
WITH (oids = false);
