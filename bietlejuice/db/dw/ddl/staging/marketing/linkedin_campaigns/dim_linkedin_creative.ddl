DROP TABLE IF EXISTS staging.dim_linkedin_creative;
CREATE TABLE IF NOT EXISTS staging.dim_linkedin_creative(
  sk_creative VARCHAR(100),
  id_creative VARCHAR(100),
  ts_load     timestamp
);