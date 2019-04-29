drop table if exists public.reprocessed_lead;
create table public.reprocessed_lead (
  id bigint,
  id_origin_lead bigint
);