drop table if exists janus.dim_bank;
create table janus.dim_bank (
  sk_bank bigint primary key,
  id_bank bigint,
  code varchar,
  name varchar,
  febraban_name varchar,
  featured_rank integer,
  ts_created timestamp,
  ts_updated timestamp,
  ts_load timestamp
);

ALTER TABLE janus.dim_bank OWNER TO airflow;