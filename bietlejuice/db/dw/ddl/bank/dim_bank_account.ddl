drop table if exists bank.dim_bank_account;

create table if not exists bank.dim_bank_account (
  sk_bank_account bigint,
  id_bank_account bigint,
  account_number varchar,
  account_type varchar,
  agency_number varchar,
  updated_at timestamp,
  created_at timestamp,
  ts_load timestamp
)
;
