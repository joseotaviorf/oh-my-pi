DROP TABLE IF EXISTS agent.fact_daily_accredited_agent;
CREATE TABLE agent.fact_daily_accredited_agent (
    sk_date BIGINT,
    sk_agent BIGINT,
    sk_work_contract BIGINT,
    sk_company BIGINT,
    allocated_slots BIGINT,
    days_since_last_contract_changed INT,
    days_since_last_activation_changed INT,
    days_since_last_business_context_changed INT,
    is_last_status_of_day BOOLEAN,
    ts_validity_started TIMESTAMP,
    ts_validity_ended TIMESTAMP,
    ts_load TIMESTAMP
)
SORTKEY(sk_date)
;

ALTER TABLE agent.fact_daily_accredited_agent OWNER TO databricks;