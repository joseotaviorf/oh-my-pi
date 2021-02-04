DROP TABLE public.potential_listings_house_b2b;
CREATE TABLE public.potential_listings_house_b2b (
	id int8 NULL,
	sk_condo int8 NULL,
	sk_house_listing int8 NULL,
	sk_partner int8 NULL,
	sk_autonomous_agent int8 NULL,
	is_exclusive int2 NULL,
	is_autonomous_agent bool NULL,
	house_usuario_que_cadastrou_id int4 NULL
);

CREATE INDEX pot_list_house_b2b_id_idx ON public.potential_listings_house_b2b USING btree (id);