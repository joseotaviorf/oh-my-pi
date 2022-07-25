drop table if exists public.bdg_listing_rent_flows_agent_daily_allocations;
create table public.bdg_listing_rent_flows_agent_daily_allocations(
  sk_listing_rent_flow bigint,
  sk_date integer,
  sk_agent integer,
  sk_slot_date_agent bigint,
  dt_timestamp timestamp default getdate()
);