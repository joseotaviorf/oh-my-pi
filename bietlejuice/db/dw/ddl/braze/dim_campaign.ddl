CREATE SCHEMA IF NOT EXISTS braze;
DROP TABLE IF EXISTS braze.dim_campaign;
CREATE TABLE braze.dim_campaign (
  sk_campaign VARCHAR,
  user_type VARCHAR,
  campaign_name VARCHAR,
  campaign_description VARCHAR,
  schedule_type VARCHAR,
  is_archived BOOLEAN,
  is_draft BOOLEAN,
  ts_first_sent TIMESTAMP,
  ts_last_sent TIMESTAMP,
  ts_created TIMESTAMP,
  ts_updated TIMESTAMP,
  ts_load TIMESTAMP  
);
ALTER TABLE braze.dim_campaign OWNER TO databricks;
CALL grant_all_permissions_on_schema('braze');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA braze TO GROUP etl;
GRANT ALL ON SCHEMA braze TO GROUP ETL;
