drop table if exists janus.dim_reservation;
create table janus.dim_reservation (
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

ALTER TABLE janus.dim_reservation OWNER TO airflow;