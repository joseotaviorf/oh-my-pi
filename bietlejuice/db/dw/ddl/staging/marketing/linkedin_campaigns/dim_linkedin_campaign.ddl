DROP TABLE IF EXISTS staging.dim_linkedin_campaign;
CREATE TABLE IF NOT EXISTS staging.dim_linkedin_campaign(
  sk_campaign        VARCHAR(50),
  id_campaign        VARCHAR(50),
  campaign_name      VARCHAR(100),
  id_account         VARCHAR(50),
  ts_load            timestamp
);