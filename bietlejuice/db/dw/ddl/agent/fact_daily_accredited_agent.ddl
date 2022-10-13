DROP TABLE IF EXISTS agent.fact_daily_accredited_agent;
CREATE TABLE agent.fact_daily_accredited_agent (
    sk_date BIGINT,
    sk_agent BIGINT,
    sk_work_contract BIGINT,
    sk_company BIGINT,
    allocated_slots INT,
    is_last_status_of_day BOOLEAN,
    ts_load TIMESTAMP
)
SORTKEY(sk_date)
;

ALTER TABLE agent.fact_daily_accredited_agent OWNER TO databricks;