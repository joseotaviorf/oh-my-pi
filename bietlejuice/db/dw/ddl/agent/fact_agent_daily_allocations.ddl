DROP TABLE IF EXISTS agent.fact_agent_daily_allocations;
CREATE TABLE agent.fact_agent_daily_allocations (
    sk_agent BIGINT NOT NULL,
    sk_slot_date BIGINT,
    sk_agent_region VARCHAR(50),
    sk_slot_date_agent BIGINT,
    id_work_contract INTEGER,
    allocated_slots INTEGER,
    allocated_slots_0 INTEGER,
    agent_business_context VARCHAR(10),
    max_slots_allocation_available INTEGER,
    area VARCHAR(50),
    ts_first_visit TIMESTAMP,
    ts_load TIMESTAMP,
    PRIMARY KEY(sk_slot_date_agent)
);

ALTER TABLE agent.fact_agent_daily_allocations OWNER TO databricks;