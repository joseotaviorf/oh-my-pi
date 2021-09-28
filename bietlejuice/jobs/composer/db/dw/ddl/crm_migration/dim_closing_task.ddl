DROP TABLE IF EXISTS crm_migration.dim_closing_task;
CREATE TABLE crm_migration.dim_closing_task (
    sk_task VARCHAR,
    score_factor INT, 
    hours_task_start_to_completed FLOAT, 
    version INT,
    origin VARCHAR,
    titles VARCHAR(2000),
	workgroups VARCHAR(2000),
    type VARCHAR,
    description VARCHAR(5000),
    subject VARCHAR,
    flg_solved BOOLEAN,
    is_task_auto_completed BOOLEAN,
    ts_start TIMESTAMP,
    ts_completed TIMESTAMP,
    ts_silenced_until TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE crm_migration.dim_closing_task OWNER TO airflow;

CALL grant_all_permissions_on_schema('crm_migration');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA crm_migration TO GROUP etl;
GRANT ALL ON SCHEMA crm_migration TO GROUP ETL; 