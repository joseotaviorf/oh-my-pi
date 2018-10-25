drop table if exists public.house_listing;
CREATE TABLE public.house_listing (
	id int8 NOT NULL,
	status varchar,
	aluguel int4,
	tipo_porteiro varchar,
	"version" int8 NOT NULL,
	min_version_time timestamp,
	max_version_time timestamp,
	nr_renting int8,
	first_publication_date timestamp,
	de_publication_date timestamp,
	start_version_category varchar,
	end_version_category varchar,
	contract_id int8,
	is_last_version int8,
	CONSTRAINT house_listing_pk PRIMARY KEY (id,"version")
)
WITH (
	OIDS=FALSE
) ;
CREATE INDEX house_listing_idx_max_v ON public.house_listing (max_version_time DESC) ;
CREATE INDEX house_listing_idx_min_v ON public.house_listing (min_version_time DESC) ;
CREATE INDEX house_listing_idx ON public.house_listing (id ASC) ;