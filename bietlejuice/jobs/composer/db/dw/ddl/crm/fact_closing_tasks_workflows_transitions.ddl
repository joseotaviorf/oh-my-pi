DROP TABLE IF EXISTS crm.fact_closing_tasks_workflows_transitions;
CREATE TABLE crm.fact_closing_tasks_workflows_transitions (
	sk_transition VARCHAR PRIMARY KEY,
	sk_workflow VARCHAR,
	sk_origin_task VARCHAR,
	sk_destination_task VARCHAR,
	sk_transitioned_date INT,
	is_end_of_workflow BOOLEAN,
	ts_load TIMESTAMP
);
ALTER TABLE crm.fact_closing_tasks_workflows_transitions OWNER TO airflow;
CALL grant_all_permissions_on_schema('crm');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA crm TO GROUP etl;
GRANT ALL ON SCHEMA crm TO GROUP ETL;