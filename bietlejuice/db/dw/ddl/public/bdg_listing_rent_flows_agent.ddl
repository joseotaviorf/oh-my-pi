DROP TABLE IF EXISTS public.bdg_listing_rent_flows_agent;
CREATE TABLE public.bdg_listing_rent_flows_agent(
  sk_listing_rent_flow BIGINT,
  sk_date INTEGER,
  sk_agent INTEGER,
  sk_slot_date_agent BIGINT,
  dt_timestamp TIMESTAMP default getdate()
);