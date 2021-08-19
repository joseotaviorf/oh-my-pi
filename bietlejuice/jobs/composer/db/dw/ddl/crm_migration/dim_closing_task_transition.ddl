DROP TABLE IF EXISTS crm_migration.dim_closing_task_transition;
CREATE TABLE crm_migration.dim_closing_task_transition (
	sk_transition VARCHAR PRIMARY KEY,
	origin_type VARCHAR,
	destination_type VARCHAR,
	conclusion_option VARCHAR,
	conclusion_context VARCHAR,
	contact_channel VARCHAR,
	status VARCHAR,
	ts_transitioned TIMESTAMP,
	ts_load TIMESTAMP
);
ALTER TABLE crm_migration.dim_closing_task_transition OWNER TO airflow;
