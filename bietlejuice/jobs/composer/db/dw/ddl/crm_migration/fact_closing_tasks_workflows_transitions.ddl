DROP TABLE IF EXISTS crm_migration.fact_closing_tasks_workflows_transitions;
CREATE TABLE crm_migration.fact_closing_tasks_workflows_transitions (
	sk_transition VARCHAR PRIMARY KEY,
	sk_workflow VARCHAR,
	sk_origin_task VARCHAR,
	sk_destination_task VARCHAR,
	sk_transitioned_date VARCHAR,
	is_end_of_workflow BOOLEAN,
	ts_load TIMESTAMP,
	year INT,
	month INT,
	day INT
);
ALTER TABLE crm_migration.fact_closing_tasks_workflows_transitions OWNER TO airflow;
