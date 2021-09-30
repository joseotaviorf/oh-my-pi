DROP TABLE IF EXISTS agents_availability.fact_inspector_daily_allocations;
CREATE TABLE agents_availability.fact_inspector_daily_allocations (
  sk_agent BIGINT,
  sk_agent_region BIGINT,
  sk_agent_slot_date BIGINT,
  sk_region BIGINT,
  sk_slot_date BIGINT,
  sk_work_contract BIGINT,
  agent_type VARCHAR,
  allocated_slots SMALLINT,
  max_slots_allocation_available SMALLINT,
  specific_allocated_slots SMALLINT,
  dt_first_inspection DATE,
  ts_load TIMESTAMP
);
ALTER TABLE agents_availability.fact_inspector_daily_allocations OWNER TO airflow;

CALL grant_all_permissions_on_schema('agents_availability');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA agents_availability TO GROUP etl;
GRANT ALL ON SCHEMA agents_availability TO GROUP ETL;