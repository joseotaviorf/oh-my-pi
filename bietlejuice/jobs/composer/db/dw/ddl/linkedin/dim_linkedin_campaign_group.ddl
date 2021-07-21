CREATE SCHEMA IF NOT EXISTS linkedin;

DROP TABLE IF EXISTS linkedin.dim_linkedin_campaign_group;
CREATE TABLE IF NOT EXISTS linkedin.dim_linkedin_campaign_group(
  sk_campaign_group   INTEGER,
  id_campaign_group   INTEGER,
  id_account          INTEGER,
  campaign_group_name VARCHAR(255),
  account_name        VARCHAR(255),
  ts_load             TIMESTAMP
);
ALTER TABLE linkedin.dim_linkedin_campaign_group OWNER TO databricks;

CALL grant_all_permissions_on_schema('linkedin');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA linkedin TO GROUP etl;
GRANT ALL ON SCHEMA linkedin TO GROUP ETL;