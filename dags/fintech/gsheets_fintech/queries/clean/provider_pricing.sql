SELECT
  external_product_code,
  product_name,
  provider_code,
  provider,
  CAST(unit_price AS DECIMAL(10, 2)) AS unit_price,
  CAST(included_monthly AS DECIMAL(10, 2)) AS included_monthly,
  CAST(included_annual AS DECIMAL(10, 2)) AS included_annual,
  CAST(exceed_unit_price AS DECIMAL(10, 2)) AS exceed_unit_price,
  IF(LOWER(is_group_feature) = 'true', TRUE, FALSE) AS is_group_feature,
  group_feature,
  CAST(group_feature_price AS DECIMAL(10, 2)) AS group_feature_price,
  CAST(weight AS DECIMAL(10, 2)) AS weight,
  TO_DATE(valid_from, 'd/M/y') AS valid_from,
  TO_DATE(valid_to, 'd/M/y') AS valid_to
FROM datalake_gsheets_raw.provider_pricing
