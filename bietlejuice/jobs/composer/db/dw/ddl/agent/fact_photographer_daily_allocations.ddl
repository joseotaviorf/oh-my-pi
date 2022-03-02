DROP TABLE IF EXISTS agent.fact_photographer_daily_allocations;
CREATE TABLE agent.fact_photographer_daily_allocations (
    sk_agent BIGINT NOT NULL,
    sk_slot_date BIGINT,
    sk_agent_region VARCHAR(50),
    sk_slot_date_agent BIGINT,
    id_work_contract INTEGER,
    id_dados_fotografo INTEGER,
    allocated_slots INTEGER,
    allocated_slots_0 INTEGER,
    max_slots_allocation_available INTEGER,
    area VARCHAR(50),
    ts_load TIMESTAMP,
    CONSTRAINT fact_photographer_daily_allocations PRIMARY KEY(sk_slot_date_agent)
);

ALTER TABLE agent.fact_photographer_daily_allocations OWNER TO databricks;