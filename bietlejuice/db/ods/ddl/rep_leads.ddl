drop table public.rep_leads;
create table public.rep_leads (
  lead_id bigint,
  lead_type varchar(255),
  lead_origin varchar(255),
  utm_source varchar(255),
  utm_medium varchar(255),
  branded_lead boolean,
  b2b_lead boolean,
  reprocessed_flg boolean
);

CREATE INDEX rpl_lead_id_idx ON public.rep_leads USING btree (lead_id);
