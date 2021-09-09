DROP TABLE IF EXISTS agents_availability.fact_inspector_allocations;
CREATE TABLE agents_availability.fact_inspector_allocations (
  sk_agent BIGINT,
  sk_agent_region BIGINT,
  sk_agent_slot_date BIGINT,
  sk_region_code_inspector BIGINT,
  sk_slot_date BIGINT,
  sk_slot_date_hour BIGINT,
  sk_work_contract BIGINT,
  agent_type VARCHAR,
  allocated_slots SMALLINT,
  specific_allocated_slots SMALLINT,
  is_allocation_available BOOLEAN,
  ts_first_inspection TIMESTAMP,
  ts_slot_hour TIMESTAMP,
  ts_load TIMESTAMP
);
ALTER TABLE agents_availability.fact_inspector_allocations OWNER TO airflow;