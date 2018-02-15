drop table if exists datalake_raw.sortinghat_proponent;
create external table datalake_raw.sortinghat_proponent (
  id string,
  name string,
  cpf string,
  income_nature string,
  marital_status string,
  gender string,
  admission_date string,
  cell_phone string,
  phone string,
  email string,
  monthly_income string,
  will_reside string,
  location_motive string,
  second_doc_type string,
  second_doc_number string,
  second_doc_issuer string,
  second_doc_issue_date string,
  nationality string,
  birthday string,
  mother_name string,
  zipcode string,
  address string,
  address_number string,
  complement string,
  bairro string,
  city string,
  state string,
  residence_condition string,
  residence_time string,
  profession string,
  employer_name string,
  employer_phone string,
  extra_income_origin string,
  extra_income_value string,
  proposal_id string,
  boavista_score string
)
row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
with serdeproperties (
  'separatorChar' = ',',
  'quoteChar' = '\"'
)
location 's3://5a-datalake/raw/sorting_hat/Proponent/'
tblproperties (
  'skip.header.line.count' = '1'
)
;