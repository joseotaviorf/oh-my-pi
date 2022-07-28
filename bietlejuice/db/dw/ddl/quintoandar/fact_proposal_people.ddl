drop table if exists quintoandar.fact_proposal_people;
create table quintoandar.fact_proposal_people (
  sk_proposal_person bigint,
  sk_personal_document varchar,
  sk_proponent bigint,
  sk_proposal bigint,
  sk_birth_date bigint,
  sk_created_date bigint,
  expected_contract_role varchar,
  rental_motive varchar,
  brl_total_income integer,
  is_going_to_live boolean,
  is_first_proposal boolean,
  is_last_proposal boolean,
  is_user boolean,
  is_valid_cpf boolean,
  is_valid_cnpj boolean,
  ts_load timestamp
);
ALTER TABLE quintoandar.fact_proposal_people owner to databricks;