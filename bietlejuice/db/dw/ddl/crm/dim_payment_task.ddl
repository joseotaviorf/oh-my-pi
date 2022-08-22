DROP TABLE IF EXISTS crm.dim_payment_task;
CREATE TABLE crm.dim_payment_task (
	sk_task VARCHAR PRIMARY KEY,
	sk_activity VARCHAR,
	user_name_activity VARCHAR,
	event_name_activity VARCHAR,
	class_activity VARCHAR,
	previous_status_activity VARCHAR,
	type_activity VARCHAR,
	score_factor INTEGER,
	version INTEGER,
	origin VARCHAR,
	type VARCHAR,
	description VARCHAR(5000),
	subject VARCHAR,
	titles VARCHAR(2000),
	workgroups VARCHAR(2000),
	tenant_refund_status VARCHAR,
	hours_task_start_to_completed DECIMAL(10,2),
	flg_solved BOOLEAN,
	is_task_auto_completed BOOLEAN,
	ts_start TIMESTAMP,
	ts_completed TIMESTAMP,
	ts_silenced_until TIMESTAMP,
	ts_load TIMESTAMP
);

ALTER TABLE crm.dim_payment_task OWNER TO databricks;
CALL grant_all_permissions_on_schema('crm');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA crm TO GROUP etl;
GRANT ALL ON SCHEMA crm TO GROUP ETL;
