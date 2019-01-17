drop table if exists bank.dim_bank;

create table if not exists bank.dim_bank (
  sk_bank bigint,
  id_bank bigint,
  updated_at timestamp,
  created_at timestamp,
  code varchar,
  name varchar,
  febraban_name varchar,
  featured_rank integer,
  ts_load timestamp
)
;