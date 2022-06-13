DROP TABLE IF EXISTS credit.fact_fintechops_tasks;
CREATE TABLE credit.fact_fintechops_tasks (
    sk_task VARCHAR,
    sk_proposal BIGINT,
    action_user_name VARCHAR,
    documentation_policy VARCHAR,
    task_working_min FLOAT,
    ts_task_started TIMESTAMP, 
    ts_task_finished TIMESTAMP
);

ALTER TABLE credit.fact_fintechops_tasks OWNER TO airflow;
CALL grant_all_permissions_on_schema('credit');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA credit TO GROUP etl;
GRANT ALL ON SCHEMA credit TO GROUP ETL;