SELECT
  id,
  code,
  city,
  cityGroup AS city_group,
  geolocation,
  propertyType AS property_type,
  status,
  transactionType AS transaction_type,
  url,
  rentPrice AS rent_price,
  salePrice AS sale_price,
  DATE(load_date) AS dt_load,
  year,
  month,
  day
FROM
  datalake_quires_raw.properties
WHERE
  DATE(load_date) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')