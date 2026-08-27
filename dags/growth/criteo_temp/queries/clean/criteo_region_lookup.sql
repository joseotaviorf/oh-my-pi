SELECT
  postcode_range,
  CAST(start_range AS STRING),
  CAST(end_range AS STRING),
  state,
  locality
FROM datalake_gsheets_raw.criteo_region_lookup