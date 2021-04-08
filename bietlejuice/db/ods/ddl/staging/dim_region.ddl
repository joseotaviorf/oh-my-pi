DROP TABLE staging.dim_region;

CREATE TABLE staging.dim_region (
	sk_region int4 NOT NULL,
	id int4,
	"level" varchar(255),
	name varchar(200),
	macro_id int4,
	macro_name varchar(200),
	city_id int4,
	city_name varchar(200),
	city_group varchar(200),
	city_ddd varchar(2),
	region_code varchar(10),
	region_code_deprecated varchar(10),
	region_code_inspector varchar(10),
	short_region_name varchar(255),
	greater_region varchar(255),
	regional varchar(255),
	regional_deprecated varchar(255),
	regional_inspection varchar(255),
	tier int4,
	dt_created timestamp,
	dt_updated timestamp,
	dt_timestamp timestamp,
	dt_first_property_created timestamp,
	dt_first_booking timestamp,
	CONSTRAINT dim_region_pkey PRIMARY KEY (sk_region)
) ;
