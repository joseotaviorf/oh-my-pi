SELECT
  id AS id_house,
  query,
  property_type,
  long_description,
  location,
  query_type,
  query_business_context,
  relevance,
  CAST(area AS DOUBLE) AS area,
  CAST(bedrooms AS DOUBLE) AS bedrooms,
  CAST(bathrooms AS DOUBLE) AS bathrooms,
  CAST(suites AS DOUBLE) AS suites,
  CAST(parking_slots AS DOUBLE) AS parking_slots,
  CAST(price AS DOUBLE) AS price,
  iptu_per_month,
  CAST(condominium_per_month AS DOUBLE) AS condominium_per_month,
  accept_pets,
  is_near_subway,
  is_furnished,
  ingestion_date AS dt_ingested,
  amenities,
  installations,
  year,
  month,
  day
FROM
  datalake_text2rank_cross_encoder_dataset_raw.cross_encoder_training_dataset
WHERE
  MAKE_DATE(year, month, day) = DATE('{load_start_date}')
