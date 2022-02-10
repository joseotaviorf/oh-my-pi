DROP TABLE IF EXISTS crm.dim_closing_task_workflow;
CREATE TABLE crm.dim_closing_task_workflow (
	sk_workflow VARCHAR PRIMARY KEY,
	status VARCHAR,
	ts_started TIMESTAMP,
	ts_updated TIMESTAMP,
	ts_ended TIMESTAMP,
	ts_load TIMESTAMP
);
ALTER TABLE crm.dim_closing_task_workflow OWNER TO airflow;
CALL grant_all_permissions_on_schema('crm');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA crm TO GROUP etl;
GRANT ALL ON SCHEMA crm TO GROUP ETL;