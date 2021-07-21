CREATE SCHEMA IF NOT EXISTS linkedin;

DROP TABLE IF EXISTS linkedin.dim_linkedin_campaign;
CREATE TABLE IF NOT EXISTS linkedin.dim_linkedin_campaign(
  sk_campaign        INTEGER PRIMARY KEY,
  id_campaign        INTEGER,
  campaign_name      VARCHAR(255),
  cost_type          VARCHAR(50),
  type               VARCHAR(50),
  locale_country     VARCHAR(50),
  locale_language    VARCHAR(50),
  ts_load            TIMESTAMP
);
ALTER TABLE linkedin.dim_linkedin_campaign OWNER TO databricks;

CALL grant_all_permissions_on_schema('linkedin');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA linkedin TO GROUP etl;
GRANT ALL ON SCHEMA linkedin TO GROUP ETL;