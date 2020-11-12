DROP TABLE IF EXISTS marketing_costs.dim_linkedin_campaign_group;
CREATE TABLE IF NOT EXISTS marketing_costs.dim_linkedin_campaign_group(
  sk_campaign_group   VARCHAR(100),
  id_campaign_group   VARCHAR(100),
  id_account          VARCHAR(100),
  campaign_group_name VARCHAR(255),
  account_name        VARCHAR(255),
  year                INTEGER,
  month               INTEGER,
  day                 INTEGER,
  ts_load             TIMESTAMP
);