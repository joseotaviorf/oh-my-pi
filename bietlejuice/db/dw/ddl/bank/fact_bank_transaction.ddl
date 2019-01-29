drop table if exists bank.fact_bank_transaction;

create table if not exists bank.fact_bank_transaction (
  sk_bank_transaction bigint,
  ts_transaction timestamp,
  sk_transaction bigint,
  value numeric(22,2),
  sk_bank_account integer,
  id_house bigint,
  sk_user_recipient bigint,
  sk_bank integer,
  type varchar,
  ts_updated timestamp,
  ts_created timestamp,
  ts_load timestamp
)
;
