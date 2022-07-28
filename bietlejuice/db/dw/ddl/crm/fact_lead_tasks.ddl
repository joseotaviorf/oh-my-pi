DROP TABLE IF EXISTS crm.fact_lead_tasks;
CREATE TABLE crm.fact_lead_tasks (
    sk_lead INTEGER,
    sk_task VARCHAR,
    sk_created_date INTEGER,
    sk_first_realized_date INTEGER,
    sk_first_resolved_date INTEGER,
    sk_user_first_assignee INTEGER,
    sk_user_first_resolver INTEGER,
    is_closed BOOLEAN,
    ts_load TIMESTAMP
);
ALTER TABLE crm.fact_lead_tasks OWNER TO airflow;
CALL grant_all_permissions_on_schema('crm');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA crm TO GROUP etl;
GRANT ALL ON SCHEMA crm TO GROUP ETL;