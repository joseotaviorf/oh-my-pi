DROP TABLE public.potential_listings_rep_leads;
CREATE TABLE public.potential_listings_rep_leads (
	id int8 NULL,
	lead_type varchar(255) NULL,
	lead_origin varchar(255) NULL,
	reprocessed_flg bool NULL,
	utm_source varchar(255) NULL,
	utm_medium varchar(255) NULL,
	branded_lead bool NULL
);

CREATE INDEX pot_list_rep_leads_id_idx ON public.potential_listings_rep_leads USING btree (id);