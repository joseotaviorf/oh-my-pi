DROP TABLE IF EXISTS crm.fact_payment_tasks;
CREATE TABLE crm.fact_payment_tasks (
    sk_task VARCHAR,
    sk_receiver BIGINT,
    sk_start_date BIGINT,
    sk_completed_date BIGINT,
    sk_origin VARCHAR,
    sk_activity  VARCHAR,
    sk_assignee BIGINT,
    sk_user_action BIGINT,
    sk_user_activity BIGINT,
    sk_action_date BIGINT,
    sk_contract BIGINT,
    sk_house_listing BIGINT,
    sk_house_owner BIGINT,
    sk_tenant BIGINT,
    sk_task_action_start_date BIGINT,
    sk_task_action_end_date BIGINT,
    ticket_number_activity BIGINT,
    discount_months_activity BIGINT,
    discount_percentage_activity DECIMAL(6,6),
    discount_amount_activity DECIMAL(14,2),
    discounted_rental_activity DECIMAL(14,2),
    rental_amount_activity DECIMAL(14,2),
    action_user_name VARCHAR,
    action_type VARCHAR,
    type_activity VARCHAR,
    task_action_type VARCHAR,
    task_user_action_resolve_hours DECIMAL(11,1),
    ts_action TIMESTAMP,
    ts_task_action_start TIMESTAMP,
    ts_task_action_end TIMESTAMP,
    ts_activity_transferred TIMESTAMP,
    ts_activity_requested TIMESTAMP,
    ts_activity_transition_created TIMESTAMP,
    ts_load TIMESTAMP
);

ALTER TABLE crm.fact_payment_tasks OWNER TO databricks;
CALL grant_all_permissions_on_schema('crm');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA crm TO GROUP etl;
GRANT ALL ON SCHEMA crm TO GROUP ETL;
