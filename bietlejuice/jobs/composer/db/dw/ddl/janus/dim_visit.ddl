drop table if exists janus.dim_visit;
create table janus.dim_visit (
  sk_visit bigint primary key,
  id_visit bigint,
  code_visit varchar(200),
  dt_visit date,
  slot integer,
  slot_count integer,
  type integer,
  status varchar(50),
  booking_type varchar(255),
  ts_created timestamp,
  ts_updated timestamp,
  ts_load timestamp
);