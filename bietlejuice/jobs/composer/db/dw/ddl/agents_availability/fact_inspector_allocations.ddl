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
  dt_first_inspection DATE,
  ts_slot_hour TIMESTAMP,
  ts_load TIMESTAMP
);
ALTER TABLE agents_availability.fact_inspector_allocations OWNER TO airflow;

CALL grant_all_permissions_on_schema('agents_availability');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA agents_availability TO GROUP etl;
GRANT ALL ON SCHEMA agents_availability TO GROUP ETL;