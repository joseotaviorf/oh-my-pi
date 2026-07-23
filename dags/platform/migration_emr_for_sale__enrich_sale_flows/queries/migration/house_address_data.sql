WITH house AS (
  SELECT
    id,
    id_address_data,
    has_seller_debt_payments,
    house_registration_status,
    land_tenure,
    ts_house_created,
    ts_last_house_updated
  FROM (
    SELECT DISTINCT
      h.id,
      h.id_address_data,
      h.has_seller_debt_payments,
      h.house_registration_status,
      h.land_tenure,
      h.ts_created AS ts_house_created,
      h.ts_updated AS ts_last_house_updated,
      h.ts_updated,
      MAX(h.ts_updated) OVER (PARTITION BY h.id) AS _w
    FROM datalake_sales_flow_clean.house AS h
    WHERE
      h.year <= STRUCT(year AS year)
      AND h.month <= STRUCT(month AS month)
      AND h.day <= STRUCT(day AS day)
  ) AS _t
  WHERE
    h.ts_updated = _w
)
SELECT DISTINCT
  h.id AS id_house,
  h.id_address_data,
  h.house_registration_status,
  h.land_tenure,
  ad.street,
  ad.number,
  ad.complement,
  ad.neighborhood,
  ad.city,
  ad.state,
  ad.zip_code,
  CONCAT(
    COALESCE(ad.street, 'street is empty'),
    ', ',
    COALESCE(ad.number, 'number is empty'),
    ', ',
    COALESCE(ad.complement, 'number is empty'),
    ', ',
    COALESCE(ad.neighborhood, 'neighborhood is empty'),
    ', ',
    COALESCE(ad.city, 'city is empty'),
    ', ',
    COALESCE(ad.state, 'state is empty'),
    ', ',
    COALESCE(ad.zip_code, 'zip code is empty')
  ) AS address,
  h.has_seller_debt_payments,
  h.ts_house_created,
  h.ts_last_house_updated,
  ad.ts_created,
  ad.ts_updated,
  ad.year,
  ad.day,
  ad.month
FROM datalake_sales_flow_clean.address_data AS ad
JOIN house AS h
  ON h.id_address_data = ad.id
WHERE
  ad.year = STRUCT(year AS year)
  AND ad.month = STRUCT(month AS month)
  AND ad.day = STRUCT(day AS day)