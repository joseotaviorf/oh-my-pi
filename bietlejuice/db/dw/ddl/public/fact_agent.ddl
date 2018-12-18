DROP TABLE IF EXISTS public.fact_agent ;
CREATE TABLE public.fact_agent (
  sk_agent INTEGER,
  sk_slot_date INTEGER,
  available_slots INTEGER,
  available_slots_0 INTEGER,
  total_slots INTEGER,
  area VARCHAR(10),
  sk_agent_region VARCHAR(20),
  sk_slot_date_agent BIGINT,
  dt_first_visit TIMESTAMP,
  flg_available_next_days BOOLEAN,
  sk_contract_type INTEGER,
  dt_timestamp TIMESTAMP default getdate()
);