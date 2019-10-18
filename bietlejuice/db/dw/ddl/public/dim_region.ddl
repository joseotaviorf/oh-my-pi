drop table if exists dim_region;
create table if not exists dim_region (
  sk_region integer,
  id integer,
  level varchar,
  name varchar,
  macro_id integer,
  macro_name varchar,
  city_id integer,
  city_name varchar,
  city_group varchar,
  city_ddd varchar(2),
  region_code varchar,
  region_code_deprecated varchar,
  region_code_inspector varchar,
  short_region_name varchar,
  greater_region varchar,
  regional varchar,
  dt_created timestamp without time zone,
  dt_updated timestamp without time zone,
  dt_timestamp timestamp without time zone,
  dt_first_property_created timestamp,
  dt_first_booking timestamp
);
