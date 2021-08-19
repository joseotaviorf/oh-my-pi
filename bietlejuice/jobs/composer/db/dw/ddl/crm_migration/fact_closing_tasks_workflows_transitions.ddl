DROP TABLE IF EXISTS crm_migration.fact_closing_tasks_workflows_transitions;
CREATE TABLE crm_migration.fact_closing_tasks_workflows_transitions (
	sk_transition VARCHAR PRIMARY KEY,
	sk_workflow VARCHAR,
	sk_origin_task VARCHAR,
	sk_destination_task VARCHAR,
	sk_transitioned_date INT,
	is_end_of_workflow BOOLEAN,
	ts_load TIMESTAMP
);
ALTER TABLE crm_migration.fact_closing_tasks_workflows_transitions OWNER TO airflow;
