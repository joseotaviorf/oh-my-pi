drop table if exists janus.fact_bank_transaction;
create table if not exists janus.fact_bank_transaction (
  sk_bank_transaction bigint,
  sk_bank_account integer,
  sk_user_recipient bigint,
  sk_bank integer,
  sk_transaction bigint,
  -- TODO review raw ids in facts
  id_house bigint,
  value numeric(22,2),
  type varchar,
  ts_transaction timestamp,
  ts_updated timestamp,
  ts_created timestamp,
  ts_load timestamp
);

ALTER TABLE janus.fact_bank_transaction OWNER TO airflow;
