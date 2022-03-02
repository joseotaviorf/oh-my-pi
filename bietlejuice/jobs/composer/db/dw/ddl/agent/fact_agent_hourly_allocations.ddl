DROP TABLE IF EXISTS agent.fact_agent_hourly_allocations;
CREATE TABLE agent.fact_agent_hourly_allocations (
    sk_agent BIGINT NOT NULL,
    sk_slot_date BIGINT,
    sk_slot_date_hour BIGINT,
    sk_agent_region VARCHAR(50),
    sk_slot_date_agent BIGINT,
    id_work_contract INTEGER,
    ts_slot_hour TIMESTAMP,
    allocated_slots INTEGER,
    allocated_slots_0 INTEGER,
    is_allocation_available BOOLEAN,
    area varchar(50),
    ts_first_visit TIMESTAMP,
    ts_load TIMESTAMP,
    CONSTRAINT fact_agent_hourly_allocations PRIMARY KEY(sk_slot_date_agent,sk_slot_date_hour)
);

ALTER TABLE agent.fact_agent_hourly_allocations OWNER TO databricks;