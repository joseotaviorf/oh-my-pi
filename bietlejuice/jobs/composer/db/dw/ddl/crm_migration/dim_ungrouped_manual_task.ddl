DROP TABLE IF EXISTS crm_migration.dim_ungrouped_manual_task;
CREATE TABLE crm_migration.dim_ungrouped_manual_task (
	sk_task VARCHAR PRIMARY KEY,
	score_factor INTEGER,
	version INTEGER,
	origin VARCHAR,
	type VARCHAR,
	description VARCHAR(5000),
	subject VARCHAR,
	titles VARCHAR(2000),
	workgroups VARCHAR(2000),
	hours_task_start_to_completed FLOAT,
	flg_solved BOOLEAN,
	is_task_auto_completed BOOLEAN,
	ts_start TIMESTAMP,
	ts_completed TIMESTAMP,
	ts_silenced_until TIMESTAMP,
	ts_load TIMESTAMP
);

ALTER TABLE crm_migration.dim_ungrouped_manual_task OWNER TO airflow;
CALL grant_all_permissions_on_schema('crm_migration');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA crm_migration TO GROUP etl;
GRANT ALL ON SCHEMA crm_migration TO GROUP ETL;
