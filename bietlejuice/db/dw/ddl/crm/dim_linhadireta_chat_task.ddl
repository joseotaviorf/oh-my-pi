DROP TABLE IF EXISTS crm.dim_linhadireta_chat_task;
CREATE TABLE crm.dim_linhadireta_chat_task (
	sk_task VARCHAR PRIMARY KEY,
	score_factor INTEGER,
	version INTEGER,
	origin VARCHAR,
	type VARCHAR,
	description VARCHAR(5000),
	subject VARCHAR,
	titles VARCHAR(2000),
	workgroups VARCHAR(2000),
	hours_task_start_to_completed DECIMAL(10,2),
	flg_solved BOOLEAN,
	is_task_auto_completed BOOLEAN,
	ts_start TIMESTAMP,
	ts_completed TIMESTAMP,
	ts_silenced_until TIMESTAMP,
	ts_load TIMESTAMP
);

ALTER TABLE crm.dim_linhadireta_chat_task OWNER TO airflow;
CALL grant_all_permissions_on_schema('crm');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA crm TO GROUP etl;
GRANT ALL ON SCHEMA crm TO GROUP ETL;