DROP TABLE IF EXISTS crm_migration.fact_lead_tasks;
CREATE TABLE crm_migration.fact_lead_tasks (
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
ALTER TABLE crm_migration.fact_lead_tasks OWNER TO airflow;
CALL grant_all_permissions_on_schema('crm_migration');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA crm_migration TO GROUP etl;
GRANT ALL ON SCHEMA crm_migration TO GROUP ETL;