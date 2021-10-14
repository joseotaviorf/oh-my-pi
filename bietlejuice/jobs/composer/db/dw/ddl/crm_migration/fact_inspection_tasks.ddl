DROP TABLE IF EXISTS crm_migration.fact_inspection_tasks;
CREATE TABLE crm_migration.fact_inspection_tasks (
    sk_task VARCHAR,
    sk_receiver BIGINT,
    sk_origin BIGINT,
    sk_assignee BIGINT,
    sk_user_action BIGINT,
    sk_inspection BIGINT,
    sk_contract BIGINT,
    sk_house_listing BIGINT,
    sk_house_owner BIGINT,
    sk_tenant BIGINT,
    sk_start_date BIGINT,
    sk_completed_date BIGINT,
    sk_action_date BIGINT,
    sk_task_action_start_date BIGINT,
    sk_task_action_end_date BIGINT,
    action_user_name VARCHAR,
    action_type VARCHAR,
    task_action_type VARCHAR,
    task_user_action_resolve_hours DECIMAL(10,1),
    ts_action TIMESTAMP,
    ts_task_action_start TIMESTAMP,
    ts_task_action_end TIMESTAMP,
    ts_load TIMESTAMP
);

ALTER TABLE crm_migration.fact_inspection_tasks OWNER TO airflow;
CALL grant_all_permissions_on_schema('crm_migration');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA crm_migration TO GROUP etl;
GRANT ALL ON SCHEMA crm_migration TO GROUP ETL;