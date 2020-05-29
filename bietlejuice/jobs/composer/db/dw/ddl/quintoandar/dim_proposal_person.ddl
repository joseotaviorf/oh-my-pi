drop table if exists quintoandar.dim_proposal_person;
create table quintoandar.dim_proposal_person (
  sk_proposal_person bigint primary key,
  full_name varchar,
  phone_number varchar,
  email varchar,
  personal_document varchar,
  personal_document_type varchar,
  employment_bond varchar,
  number_of_dependents integer,
  current_house_situation varchar,
  has_contributed_to_current_house boolean,
  gender varchar,
  marital_status varchar,
  state_code bigint,
  dt_birth date,
  ts_created timestamp,
  ts_updated timestamp,
  ts_load timestamp
)
;
