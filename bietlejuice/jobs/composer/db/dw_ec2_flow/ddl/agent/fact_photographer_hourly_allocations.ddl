DROP TABLE IF EXISTS agent.fact_photographer_hourly_allocations;
CREATE TABLE agent.fact_photographer_hourly_allocations(
  sk_agent                 INTEGER,
  sk_slot_date             INTEGER,
  sk_slot_date_hour        BIGINT,
  sk_agent_region          VARCHAR(20),
  sk_slot_date_agent       BIGINT,
  id_work_contract         INTEGER,
  id_dados_fotografo       INTEGER,
  ts_slot_hour             timestamp,
  allocated_slots          INTEGER,
  allocated_slots_0        INTEGER,
  is_allocation_available  BOOLEAN,
  area                     VARCHAR(10),
  ts_load                  TIMESTAMP default getdate()
);