drop table if exists public.dim_reservation;
create table public.dim_reservation (
  sk_reservation bigint primary key,
  id_reservation bigint,
  version int4,
  attempt int4,
  status varchar(255),
  cancellation_reason varchar(255),
  value decimal(19, 2),
  installments int4,
  is_ongoing int4,
  ts_created timestamp,
  ts_updated timestamp
);

ALTER TABLE public.dim_reservation OWNER TO databricks;