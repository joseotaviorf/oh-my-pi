drop table if exists public.reprocessed_lead;
create table public.reprocessed_lead (
  id bigint,
  id_origin_lead bigint
);

create index reprocessed_lead_id_idx on reprocessed_lead (id, id_origin_lead);
