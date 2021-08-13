DROP TABLE IF EXISTS quintoandar_temp.fact_contract_people;
CREATE TABLE quintoandar_temp.fact_contract_people (
  sk_contract_person BIGINT PRIMARY KEY,
  sk_personal_document VARCHAR,
  sk_user BIGINT,
  sk_contract BIGINT,
  sk_birth_date BIGINT,
  sk_created_date BIGINT,
  sk_updated_date BIGINT,
  contract_role VARCHAR,
  is_user BOOLEAN,
  is_valid_cpf BOOLEAN,
  is_valid_cnpj BOOLEAN,
  is_contract_user BOOLEAN,
  is_living BOOLEAN,
  is_first_contract BOOLEAN,
  is_last_contract BOOLEAN,
  ts_load TIMESTAMP
);
ALTER TABLE quintoandar_temp.fact_contract_people OWNER TO airflow;