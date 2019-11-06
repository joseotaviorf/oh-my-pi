DROP TABLE IF EXISTS agent.fact_photographer_daily_allocations;
CREATE TABLE agent.fact_photographer_daily_allocations(
  sk_agent                             INTEGER,
  sk_slot_date                         INTEGER,
  sk_slot_date_agent                   BIGINT,
  id_dados_fotografo                   INTEGER,
  allocated_slots                      INTEGER,
  allocated_slots_0                    INTEGER,
  max_slots_allocation_available       INTEGER,
  area                                 VARCHAR(10),
  sk_agent_region                      VARCHAR(20),
  id_work_contract                     INTEGER,
  ts_load                              TIMESTAMP default getdate()
);