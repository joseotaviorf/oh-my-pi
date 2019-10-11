DROP TABLE IF EXISTS public.fact_photographer_hourly_allocations;
CREATE TABLE public.fact_photographer_hourly_allocations(
  sk_agent                 INTEGER,
  sk_photographer          INTEGER,
  sk_slot_date             INTEGER,
  ts_slot_hour             TIMESTAMP,
  available_slots          INTEGER,
  available_slots_0        INTEGER,
  is_allocation_available  BOOLEAN,
  region_code              VARCHAR(10),
  sk_agent_region          VARCHAR(20),
  ts_load                  TIMESTAMP default getdate()
);