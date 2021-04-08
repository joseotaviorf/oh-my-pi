CREATE TABLE IF NOT EXISTS dw_public.dim_region (
  sk_region string,
  id string,
  level string,
  name string,
  macro_id string,
  macro_name string,
  city_id string,
  city_name string,
  city_group string,
  city_ddd string,
  region_code string,
  region_code_deprecated string,
  region_code_inspector string,
  short_region_name string,
  greater_region string,
  regional string,
  regional_deprecated string,
  regional_inspection string,
  tier string,
  dt_created string,
  dt_updated string,
  dt_timestamp string,
  dt_first_property_created string,
  dt_first_booking string
)
USING CSV
OPTIONS (
  path 's3://5a-datalake/clean/ods/dim_region',
  header 'true',
  inferSchema 'true'
)