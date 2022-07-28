CREATE SCHEMA IF NOT EXISTS casa_mineira_portal;

DROP TABLE IF EXISTS casa_mineira_portal.fact_real_estate_status;
CREATE TABLE IF NOT EXISTS casa_mineira_portal.fact_real_estate_status (
    sk_real_estate_agency INT,
    sk_consider_status_started_date INT,
    sk_consider_status_ended_date INT,
    status VARCHAR(20),
    dt_consider_status_started DATE,
    dt_consider_status_ended DATE,
    ts_load TIMESTAMP
);
ALTER TABLE casa_mineira_portal.fact_real_estate_status OWNER TO databricks;

CALL grant_all_permissions_on_schema('casa_mineira_portal');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA casa_mineira_portal TO GROUP etl;
GRANT ALL ON SCHEMA casa_mineira_portal TO GROUP ETL;
