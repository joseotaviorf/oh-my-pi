DROP TABLE IF EXISTS quintoandar.dim_contract_person;
CREATE TABLE quintoandar.dim_contract_person (
  sk_contract_person BIGINT PRIMARY KEY,
  country_code VARCHAR,
  full_name VARCHAR,
  phone_number VARCHAR,
  email VARCHAR,
  personal_document VARCHAR,
  personal_document_type VARCHAR,
  has_ongoing_contract BOOLEAN,
  gender VARCHAR,
  marital_status VARCHAR,
  state_code BIGINT,
  dt_birth DATE,
  ts_created TIMESTAMP,
  ts_updated TIMESTAMP,
  ts_load TIMESTAMP
);
ALTER TABLE quintoandar.dim_contract_person OWNER TO airflow;