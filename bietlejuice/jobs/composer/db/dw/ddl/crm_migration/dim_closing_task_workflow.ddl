DROP TABLE IF EXISTS crm_migration.dim_closing_task_workflow;
CREATE TABLE crm_migration.dim_closing_task_workflow (
	sk_workflow VARCHAR PRIMARY KEY,
	status VARCHAR,
	ts_started TIMESTAMP,
	ts_updated TIMESTAMP,
	ts_ended TIMESTAMP,
	ts_load TIMESTAMP,
	year INT,
	month INT,
	day INT
);
ALTER TABLE crm_migration.dim_closing_task_workflow OWNER TO airflow;
