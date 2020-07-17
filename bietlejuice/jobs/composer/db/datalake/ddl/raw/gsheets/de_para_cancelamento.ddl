CREATE TABLE datalake_raw.gsheets_de_para_cancelamento(
  `count` string,
  `new_reason` string,
  `reason` string,
  `reason_category` string,
  `responsible` string)
USING JSON
OPTIONS (path 's3://{OLD_DATALAKE_BUCKET}/raw/gsheets/de_para_cancelamento')
