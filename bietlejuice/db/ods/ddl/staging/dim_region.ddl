DROP TABLE staging.dim_region;

CREATE TABLE staging.dim_region (
	sk_region int4 NOT NULL,
	id int4,
	"level" varchar(30),
	name varchar(100),
	macro_id int4,
	macro_name varchar(100),
	city_id int4,
	city_name varchar(100),
	region_code varchar(10),
	short_region_name varchar(255),
	long_region_name varchar(255),
	greater_region varchar(100),
	dt_created timestamp,
	dt_updated timestamp,
	dt_timestamp timestamp,
	dt_first_property_created timestamp,
	dt_first_booking timestamp,
	days_from_first_booking int4,
	CONSTRAINT dim_region_pkey PRIMARY KEY (sk_region)
) ;