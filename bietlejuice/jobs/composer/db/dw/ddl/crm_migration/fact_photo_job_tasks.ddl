DROP TABLE IF EXISTS crm_migration.fact_photo_job_tasks;
CREATE TABLE crm_migration.fact_photo_job_tasks (
    sk_task VARCHAR,
    sk_photo_job BIGINT,
    sk_action_date BIGINT,
    sk_assignee BIGINT,
    sk_completed_date BIGINT,
    sk_house_listing BIGINT,
    sk_house_owner BIGINT,
    sk_origin BIGINT,
    sk_receiver BIGINT,
    sk_start_date BIGINT,
    sk_task_user_end_date BIGINT,
    sk_task_user_start_date BIGINT,
    sk_user_action BIGINT,
    sk_user_sales_rep BIGINT,
    action_type VARCHAR,
    action_user_name VARCHAR,
    task_user_type VARCHAR,
    task_user_resolve_hours DECIMAL(10, 1),
    ts_action TIMESTAMP,
    ts_task_user_end TIMESTAMP,
    ts_task_user_start TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE crm_migration.fact_photo_job_tasks OWNER TO airflow;
CALL grant_all_permissions_on_schema('crm_migration');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA crm_migration TO GROUP etl;
GRANT ALL ON SCHEMA crm_migration TO GROUP ETL; 