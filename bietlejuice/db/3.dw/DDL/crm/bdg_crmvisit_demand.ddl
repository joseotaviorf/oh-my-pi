drop table if exists public.bdg_crmvisit_demand;
create table if not exists public.bdg_crmvisit_demand (
  sk_visit_task varchar,
  sk_demand bigint,
  dt_timestamp timestamp
)
;