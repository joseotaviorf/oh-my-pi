drop table public.rn_lead;
create table public.rn_lead (
  rep_id integer,
  lead_id integer,
  dt_created timestamp,
  dt_closed timestamp,
  rn_first bigint,
  rn_last bigint
);

CREATE INDEX rnl_lead_id_idx ON public.rn_lead USING btree (lead_id);
