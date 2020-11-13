DROP TABLE IF EXISTS marketing_costs.dim_linkedin_creative;
CREATE TABLE IF NOT EXISTS marketing_costs.dim_linkedin_creative(
  sk_creative INTEGER,
  id_creative INTEGER,
  ts_load     TIMESTAMP
);