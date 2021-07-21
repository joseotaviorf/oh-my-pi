CREATE SCHEMA IF NOT EXISTS linkedin;

DROP TABLE IF EXISTS linkedin.dim_linkedin_creative;
CREATE TABLE IF NOT EXISTS linkedin.dim_linkedin_creative(
  sk_creative INTEGER,
  id_creative INTEGER,
  ts_load     TIMESTAMP
);
ALTER TABLE linkedin.dim_linkedin_creative OWNER TO databricks;

CALL grant_all_permissions_on_schema('linkedin');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA linkedin TO GROUP etl;
GRANT ALL ON SCHEMA linkedin TO GROUP ETL;