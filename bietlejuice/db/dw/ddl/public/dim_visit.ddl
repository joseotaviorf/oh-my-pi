drop table if exists dim_visit;
create table if not exists dim_visit (
  sk_visit integer,
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