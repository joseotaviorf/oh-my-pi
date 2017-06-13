drop table if exists public.property_listing;
CREATE TABLE public.property_listing (
	id int8 NOT NULL,
	"version" int8 NOT NULL,
	min_version_time timestamp NULL,
	max_version_time timestamp NULL,
	last_status_version varchar NULL,
	nr_listing integer null,
	nr_renting integer null,
	publication_date timestamp NULL,
	CONSTRAINT property_listing_pk PRIMARY KEY (id,"version")
)
WITH (
	OIDS=FALSE
) ;
CREATE INDEX property_listing_idx_max_v ON public.property_listing (max_version_time DESC) ;
CREATE INDEX property_listing_idx_min_v ON public.property_listing (min_version_time DESC) ;