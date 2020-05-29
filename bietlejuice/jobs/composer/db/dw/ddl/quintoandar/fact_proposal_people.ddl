drop table if exists quintoandar.fact_proposal_people;
create table quintoandar.fact_proposal_people (
  id bigint,
  cpf varchar,
  sk_proponent bigint,
  sk_proposal bigint,
  sk_birth_date bigint,
  sk_created_date bigint,
  is_user boolean,
  is_valid_cpf boolean,
  is_valid_cnpj boolean,
  expected_contract_role varchar,
  rental_motive varchar,
  is_going_to_live boolean,
  is_first_proposal boolean,
  is_last_proposal boolean,
  brl_total_income integer,
  ts_load timestamp
)
;