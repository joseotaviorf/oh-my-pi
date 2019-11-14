DROP TABLE IF EXISTS marketing.dim_linkedin_campaign_group;
CREATE TABLE IF NOT EXISTS marketing.dim_linkedin_campaign_group(
  sk_campaign_group   VARCHAR(100),
  id_campaign_group   VARCHAR(100),
  campaign_group_name VARCHAR(255),
  id_account          VARCHAR(100),
  account_name        VARCHAR(255),
  ts_load             timestamp
);