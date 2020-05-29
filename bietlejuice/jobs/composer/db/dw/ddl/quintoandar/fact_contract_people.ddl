drop table if exists quintoandar.fact_contract_people;
create table quintoandar.fact_contract_people (
  id bigint,
  cpf varchar,
  sk_user bigint,
  sk_contract bigint,
  sk_birth_date bigint,
  sk_created_date bigint,
  sk_updated_date bigint,
  contract_role varchar,
  is_user boolean,
  is_valid_cpf boolean,
  is_valid_cnpj boolean,
  is_contract_user boolean,
  is_living boolean,
  is_first_contract boolean,
  is_last_contract boolean,
  ts_load timestamp
)
;