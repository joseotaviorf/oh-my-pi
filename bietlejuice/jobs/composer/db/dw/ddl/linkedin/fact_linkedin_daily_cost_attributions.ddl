DROP TABLE IF EXISTS linkedin.fact_linkedin_daily_cost_attributions;
CREATE TABLE IF NOT EXISTS linkedin.fact_linkedin_daily_cost_attributions(
  sk_creative                                   VARCHAR(100),
  sk_campaign                                   VARCHAR(100),
  sk_campaign_group                             VARCHAR(100),
  sk_date                                       INTEGER,
  total_cost                                    DOUBLE PRECISION,
  card_clicks                                   INTEGER,
  card_impressions                              INTEGER,
  clicks                                        INTEGER,
  comments                                      INTEGER,
  company_page_clicks                           INTEGER,
  follows                                       INTEGER,
  impressions                                   INTEGER,
  likes                                         INTEGER,
  opens                                         INTEGER,
  reactions                                     INTEGER,
  shares                                        INTEGER,
  sends                                         INTEGER,
  text_url_clicks                               INTEGER,
  ts_load                                       TIMESTAMP
);
ALTER TABLE linkedin.fact_linkedin_daily_cost_attributions OWNER TO databricks;

CALL grant_all_permissions_on_schema('linkedin');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA linkedin TO GROUP etl;
GRANT ALL ON SCHEMA linkedin TO GROUP ETL;