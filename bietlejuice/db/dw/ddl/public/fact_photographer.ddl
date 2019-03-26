DROP TABLE IF EXISTS public.fact_photographer;
CREATE TABLE public.fact_photographer(
  sk_agent          INTEGER,
  sk_photographer   INTEGER,
  sk_slot_date      INTEGER,
  available_slots   INTEGER,
  available_slots_0 INTEGER,
  total_slots       INTEGER,
  area              VARCHAR(10),
  sk_agent_region   VARCHAR(20),
  ts_load           TIMESTAMP default getdate()
);