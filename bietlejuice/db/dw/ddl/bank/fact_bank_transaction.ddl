drop table if exists bank.fact_bank_transaction;

create table if not exists bank.fact_bank_transaction (
  sk_bank_transaction bigint,
  id_bank_transaction bigint,
  ts_trasaction timestamp,
  value numeric(22,2),
  sk_bank_account integer,
  house_id bigint,
  sk_user bigint,
  sk_bank integer,
  ts_load timestamp
)
;
