drop table if exists janus.dim_bank_account;
create table if not exists janus.dim_bank_account (
  sk_bank_account bigint primary key,
  id_bank_account bigint,
  account_number varchar,
  account_type varchar,
  agency_number varchar,
  ts_updated timestamp,
  ts_created timestamp,
  ts_load timestamp
);

ALTER TABLE janus.dim_bank_account OWNER TO airflow;