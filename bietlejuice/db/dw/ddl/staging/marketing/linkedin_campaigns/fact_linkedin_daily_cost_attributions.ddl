DROP TABLE staging.fact_linkedin_daily_cost_attributions;
CREATE TABLE IF NOT EXISTS staging.fact_linkedin_daily_cost_attributions(
  sk_ad        VARCHAR(50),
  sk_campaign  VARCHAR(50),
  sk_date      INTEGER,
  total_spent  DOUBLE PRECISION,
  impressions  INTEGER,
  clicks       INTEGER,
  other_clicks INTEGER,
  ts_load      TIMESTAMP
);