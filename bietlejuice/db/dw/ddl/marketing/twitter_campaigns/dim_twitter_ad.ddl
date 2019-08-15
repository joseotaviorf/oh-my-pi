DROP TABLE IF EXISTS marketing.dim_twitter_ad;
CREATE TABLE IF NOT EXISTS marketing.dim_twitter_ad(
  sk_ad              VARCHAR(50),
  id_ad              VARCHAR(50),
  tweet_id           BIGINT,
  ts_load            timestamp
);