drop table if exists bank.dim_bank;

create table bank.dim_bank (
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

ALTER TABLE bank.dim_bank OWNER TO airflow;