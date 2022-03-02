DROP TABLE IF EXISTS agent.fact_photographer_hourly_allocations;
CREATE TABLE public.fact_photographer_hourly_allocations (
    sk_agent BIGINT NOT NULL,
    sk_slot_date BIGINT,
    sk_slot_date_hour BIGINT,
    sk_agent_region VARCHAR(255),
    sk_slot_date_agent BIGINT,
    id_work_contract BIGINT,
    id_dados_fotografo BIGINT,
    ts_slot_hour TIMESTAMP,
    allocated_slots INTEGER,
    allocated_slots_0 INTEGER,
    is_allocation_available BOOLEAN,
    area VARCHAR(20),
    ts_load TIMESTAMP,
    CONSTRAINT fact_photographer_hourly_allocations PRIMARY KEY(sk_slot_date_agent, sk_slot_date_hour)
);

ALTER TABLE agent.fact_photographer_hourly_allocations OWNER TO databricks;