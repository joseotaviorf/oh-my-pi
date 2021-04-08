DROP TABLE IF EXISTS datalake_raw.gsheets_aux_regiao;
CREATE TABLE datalake_raw.gsheets_aux_regiao (
  id string,
  ddd string,
  city string,
  city_group string,
  neighbourhood string,
  region_code string,
  region_code_deprecated string,
  region_code_inspector string,
  regional string,
  regional_deprecated string,
  reginal_inspection string,
  state string,
  tier string)
USING JSON
OPTIONS ( path 's3://{OLD_DATALAKE_BUCKET}/raw/gsheets/aux_regiao')
