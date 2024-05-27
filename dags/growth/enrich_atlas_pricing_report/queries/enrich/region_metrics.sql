WITH sale_contracts AS (
  SELECT
    offer.id_house,
    'SALE' AS business_context,
    h.city,
    100*(ABS(offer.last_price_offered_by_buyer - hpp.p_50)/offer.last_price_offered_by_buyer) AS percentual_error
  FROM
    datalake_offer.sale_offer AS offer
  INNER JOIN
    datalake_ebdb_clean.house_predicted_price AS hpp
      ON offer.id_house = hpp.id_house
  INNER JOIN
    datalake_ebdb_clean.house AS h
      ON h.id = offer.id_house
  WHERE
    1=1
    AND offer.dt_sale_agreement_signed IS NOT NULL
    AND DATE_DIFF(CURRENT_DATE, DATE(offer.dt_sale_agreement_signed)) BETWEEN 0 AND 60
    AND offer.last_price_offered_by_buyer BETWEEN 100000 AND 20000000
    AND offer.id_house IS NOT NULL
    AND hpp.business_context = 'SALE'
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY offer.id_house ORDER BY offer.dt_sale_agreement_signed DESC) = 1
),
rent_contracts AS (
  SELECT
    h.id AS id_house,
    'RENT' AS business_context,
    h.city,
    100*(ABS(c.rent - hpp.p_50)/c.rent) AS percentual_error
  FROM
    datalake_ebdb_clean.contract AS c
  INNER JOIN
    datalake_ebdb_clean.house AS h
      ON h.id = c.id_house
  INNER JOIN
    datalake_ebdb_clean.house_predicted_price AS hpp
      ON h.id = hpp.id_house
  WHERE
    DATE_DIFF(CURRENT_DATE, DATE(c.ts_signed)) BETWEEN 0 AND 60
    AND hpp.business_context = 'RENT'
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY h.id ORDER BY c.ts_signed DESC) = 1
),
mdape_union AS (
  SELECT
    city,
    business_context,
    MEDIAN(percentual_error) AS mdape
  FROM
    sale_contracts
  GROUP BY ALL
  UNION ALL
  SELECT
    city,
    business_context,
    MEDIAN(percentual_error) AS mdape
  FROM
    rent_contracts
  GROUP BY ALL
)
SELECT
  dr.sk_region AS id_region,
  mun.city AS city_name,
  mun.business_context,
  ROUND(mun.mdape, 2) AS mdape_city
FROM
  mdape_union AS mun
INNER JOIN
  dw_public.dim_region AS dr
    ON mun.city = dr.city_name
      AND dr.country_code != 'MX'
