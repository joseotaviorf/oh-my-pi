CREATE TABLE datalake_raw.gsheets_taxonomy_demand(
  `app_type` string,
  `branded` string,
  `category` string,
  `channel` string,
  `completion` string,
  `first_update_source` string,
  `flg_via_reschedule` string,
  `flow` string,
  `id` string,
  `medium` string,
  `origin` string,
  `platform` string,
  `source` string,
  `utm_medium` string,
  `utm_source` string)
USING JSON
OPTIONS (path 's3://{OLD_DATALAKE_BUCKET}/raw/gsheets/taxonomy_demand')
