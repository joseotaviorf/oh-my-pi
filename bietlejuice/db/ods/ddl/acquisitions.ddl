drop table public.acquisitions;
create table public.acquisitions (
  id bigint,
  flow varchar,
  acquisition_method varchar,
  acquisition_channel varchar,
  acquisition_source varchar,
  is_doorman boolean
);

CREATE INDEX act_id_idx ON public.acquisitions USING btree (id);
