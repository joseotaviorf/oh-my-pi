drop table if exists public.dim_visit;
create table public.dim_visit (
  sk_visit integer primary key,
  id_visit integer,
  cd_visit varchar(200),
  day_visit date,
  slot integer,
  slot_count integer,
  type integer,
  status varchar(50),
  booking_type varchar(255),
  dt_created timestamp,
  dt_updated timestamp,
  dt_timestamp timestamp without time zone
);

ALTER TABLE public.dim_visit OWNER TO databricks;