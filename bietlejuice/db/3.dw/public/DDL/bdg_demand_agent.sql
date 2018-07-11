DROP TABLE IF EXISTS public.bdg_demand_agent;
CREATE TABLE public.bdg_demand_agent(
  sk_demand BIGINT,
  sk_date INTEGER,
  sk_agent INTEGER,
  sk_slot_date_agent BIGINT,
  dt_timestamp TIMESTAMP default getdate()
);