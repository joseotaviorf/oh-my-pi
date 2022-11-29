drop table if exists public.dim_region;
create table if not exists public.dim_region (
  sk_region integer primary key,
  id integer,
  id_country integer,
  macro_id integer,
  city_id integer,
  country_code VARCHAR,
  level varchar,
  name varchar,
  macro_name varchar,
  city_name varchar,
  city_group varchar,
  city_ddd varchar(2),
  region_code varchar,
  region_code_deprecated varchar,
  region_code_inspector varchar(10),
  short_region_name varchar,
  greater_region varchar,
  regional varchar,
  regional_deprecated varchar,
  regional_inspection varchar,
  tier integer,
  country_name varchar,
  dt_first_booking timestamp,
  dt_first_property_created timestamp,
  dt_created timestamp without time zone,
  dt_updated timestamp without time zone,
  dt_timestamp timestamp without time zone
);

ALTER TABLE public.dim_region OWNER TO databricks;
