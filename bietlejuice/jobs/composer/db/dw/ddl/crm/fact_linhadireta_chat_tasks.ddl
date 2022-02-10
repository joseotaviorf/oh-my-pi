DROP TABLE IF EXISTS crm.fact_linhadireta_chat_tasks;
CREATE TABLE crm.fact_linhadireta_chat_tasks (
    sk_task VARCHAR,
    sk_action_date BIGINT,
    sk_assignee BIGINT,
    sk_completed_date BIGINT,
    sk_contract BIGINT,
    sk_house_listing BIGINT,
    sk_house_owner BIGINT,
    sk_origin BIGINT,
    sk_receiver BIGINT,
    sk_start_date BIGINT,
    sk_task_action_end_date BIGINT,
    sk_task_action_start_date BIGINT,
    sk_tenant BIGINT,
    sk_user_action BIGINT,
    action_type VARCHAR,
    action_user_name VARCHAR,
    task_action_type VARCHAR,
    task_user_action_resolve_hours DECIMAL(11,1),
    ts_action TIMESTAMP,
    ts_task_action_end TIMESTAMP,
    ts_task_action_start TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE crm.fact_linhadireta_chat_tasks OWNER TO airflow;
CALL grant_all_permissions_on_schema('crm');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA crm TO GROUP etl;
GRANT ALL ON SCHEMA crm TO GROUP ETL;