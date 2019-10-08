DROP TABLE IF EXISTS marketing.dim_linkedin_ad;
CREATE TABLE IF NOT EXISTS marketing.dim_linkedin_ad(
  sk_ad              VARCHAR(50),
  id_ad              VARCHAR(50),
  ad_name            VARCHAR(100),
  ts_load            timestamp
);