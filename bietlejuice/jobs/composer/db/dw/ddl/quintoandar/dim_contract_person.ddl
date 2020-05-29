drop table if exists quintoandar.dim_contract_person;
create table quintoandar.dim_contract_person (
  sk_contract_person bigint primary key,
  full_name varchar,
  phone_number varchar,
  email varchar,
  personal_document varchar,
  personal_document_type varchar,
  has_ongoing_contract boolean,
  gender varchar,
  marital_status varchar,
  state_code bigint,
  dt_birth date,
  ts_created timestamp,
  ts_updated timestamp,
  ts_load timestamp
)
;
