drop table if exists bank.dim_bank_transaction;

create table if not exists bank.dim_bank_transaction (
  sk_bank_transaction bigint,
  id_bank_transaction bigint,
  description varchar,
  type varchar,
  updated_at timestamp,
  created_at timestamp,
  ts_load timestamp
)
;
