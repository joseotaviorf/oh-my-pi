DROP TABLE IF EXISTS marketing.dim_twitter_campaign;
CREATE TABLE IF NOT EXISTS marketing.dim_twitter_campaign(
  sk_campaign        VARCHAR(50),
  id_campaign        VARCHAR(50),
  campaign_name      VARCHAR(100),
  id_account         VARCHAR(50),
  account_name       VARCHAR(100),
  ts_load            timestamp
);