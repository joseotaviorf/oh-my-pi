drop table if exists janus.fact_bank_transaction;
create table if not exists janus.fact_bank_transaction (
  sk_bank_transaction bigint,
  sk_bank_account bigint,
  sk_user_recipient bigint,
  sk_bank bigint,
  sk_transaction_date bigint,
  -- TODO review raw ids in facts
  id_house bigint,
  value float,
  type varchar,
  ts_transaction timestamp,
  ts_updated timestamp,
  ts_created timestamp,
  ts_load timestamp
);
