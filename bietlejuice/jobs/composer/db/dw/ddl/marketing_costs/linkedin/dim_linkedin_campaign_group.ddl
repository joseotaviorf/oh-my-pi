DROP TABLE IF EXISTS marketing_costs.dim_linkedin_campaign_group;
CREATE TABLE IF NOT EXISTS marketing_costs.dim_linkedin_campaign_group(
  sk_campaign_group   INTEGER,
  id_campaign_group   INTEGER,
  id_account          INTEGER,
  campaign_group_name VARCHAR(255),
  account_name        VARCHAR(255),
  ts_load             TIMESTAMP
);