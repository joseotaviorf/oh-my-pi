DROP TABLE IF EXISTS agent.fact_agent_contract;
CREATE TABLE agent.fact_agent_contract (
    sk_agent BIGINT,
    sk_work_contract BIGINT,
    sk_company BIGINT,
    sk_last_contract_changed_date BIGINT,
    sk_last_activation_changed_date BIGINT,
    sk_last_business_context_changed_date BIGINT,
    sk_status_started_date BIGINT,
    sk_status_ended_date BIGINT,
    action VARCHAR(64),
    days_in_status FLOAT,
    ts_last_contract_changed TIMESTAMP,
    ts_last_activation_changed TIMESTAMP,
    ts_last_business_context_changed TIMESTAMP,
    ts_status_started TIMESTAMP,
    ts_status_ended TIMESTAMP,
    ts_load TIMESTAMP,
    PRIMARY KEY(sk_agent, ts_status_started)
);
ALTER TABLE agent.fact_agent_contract OWNER TO databricks;