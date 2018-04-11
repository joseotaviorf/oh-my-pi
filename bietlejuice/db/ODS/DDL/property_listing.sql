drop table if exists public.property_listing;
CREATE TABLE public.property_listing (
	id int8 NOT NULL,
	status varchar NULL,
	"version" int8 NOT NULL,
	min_version_time timestamp NULL,
	max_version_time timestamp NULL,
	nr_renting integer null,
	first_publication_date timestamp NULL,
	start_version_category varchar null,
	end_version_category varchar null,
	is_last_version int8,
	CONSTRAINT property_listing_pk PRIMARY KEY (id,"version")
)
WITH (
	OIDS=FALSE
) ;
CREATE INDEX property_listing_idx_max_v ON public.property_listing (max_version_time DESC) ;
CREATE INDEX property_listing_idx_min_v ON public.property_listing (min_version_time DESC) ;