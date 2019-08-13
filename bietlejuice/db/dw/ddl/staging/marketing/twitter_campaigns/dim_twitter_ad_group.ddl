DROP TABLE IF EXISTS staging.dim_twitter_ad_group;
CREATE TABLE IF NOT EXISTS staging.dim_twitter_ad_group(
  sk_ad_group        VARCHAR(50),
  id_ad_group        VARCHAR(50),
  ad_group_name      VARCHAR(100),
  ts_load            timestamp
);