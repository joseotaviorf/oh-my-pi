DROP TABLE IF EXISTS marketing_costs.dim_linkedin_creative;
CREATE TABLE IF NOT EXISTS marketing_costs.dim_linkedin_creative(
  sk_creative VARCHAR(100),
  id_creative VARCHAR(100),
  year        INTEGER,
  month       INTEGER,
  day         INTEGER,
  ts_load     TIMESTAMP
);