DROP TABLE IF EXISTS public.fact_agent ;
CREATE TABLE public.fact_agent (
  sk_agent INTEGER,
  sk_slot_date INTEGER,
  available_slots INTEGER,
  available_slots_0 INTEGER,
  total_slots INTEGER,
  area VARCHAR(10),
  sk_agentregion VARCHAR(20),
  sk_slot_date_agent BIGINT
);