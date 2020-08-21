drop table public.lead_city_region;

create table public.lead_city_region (
	id_lead bigint NOT NULL,
	id_region integer
);

CREATE INDEX lead_city_region_id_lead_idx ON public.lead_city_region USING btree (id_lead);
