drop table if exists janus.dim_reservation;
create table janus.dim_reservation (
  sk_reservation bigint primary key,
  id_reservation bigint,
  version integer,
  attempt integer,
  status varchar(255),
  cancellation_reason varchar(255),
  value decimal(19, 2),
  installments integer,
  is_ongoing boolean,
  ts_created timestamp,
  ts_updated timestamp,
  ts_load timestamp
);
