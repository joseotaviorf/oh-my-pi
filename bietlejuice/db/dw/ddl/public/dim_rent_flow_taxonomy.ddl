DROP TABLE IF EXISTS public.dim_rent_flow_taxonomy;

CREATE TABLE public.dim_rent_flow_taxonomy (
	sk_rent_flow_taxonomy bigint primary key,
	id_rent_flow_taxonomy bigint,
	mkt_category varchar(255),
	mkt_flow varchar(255),
	mkt_completion varchar(255),
	mkt_origin varchar(255),
	mkt_channel varchar(255),
	mkt_medium varchar(255),
	mkt_source varchar(255),
	mkt_platform varchar(255),
	ts_load timestamp
)