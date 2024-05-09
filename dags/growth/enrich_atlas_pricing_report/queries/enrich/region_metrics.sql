WITH sale_contracts AS (
  SELECT
    so.id_house,
    COALESCE(CAST(REPLACE(SUBSTRING(so.dt_sale_agreement_signed, 1, 10), '-', '') AS BIGINT), -1) AS id_sale_agreeement_signed_date,
    so.last_price_offered_by_buyer AS sale,
    dd.date AS signed_date
  FROM
    datalake_offer.sale_offer AS so
  INNER JOIN
    dw_public.dim_date AS dd
      ON dd.sk_date = COALESCE(CAST(REPLACE(SUBSTRING(so.dt_sale_agreement_signed, 1, 10), '-', '') AS BIGINT), -1)
  WHERE
    COALESCE(CAST(REPLACE(SUBSTRING(so.dt_sale_agreement_signed, 1, 10), '-', '') AS BIGINT), -1) > 0
    AND DATEDIFF(CURRENT_DATE, dd.date) <= 60
    AND so.last_price_offered_by_buyer BETWEEN 100000 AND 20000000
    AND so.id_house IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_house ORDER BY signed_date DESC) = 1
),
sale_prices_errors AS (
  SELECT DISTINCT
    sc.id_house,
    h.city AS city_name,
    p.business_context,
    100*(ABS(sc.sale - p.p_50)/sc.sale) AS percentual_error
  FROM
    sale_contracts AS sc
  INNER JOIN
    datalake_ebdb_clean.house_predicted_price_aud AS p
      ON sc.id_house = p.id_house
  INNER JOIN
    dw_sale.fact_listings AS fl
      ON sc.id_house = fl.sk_house
  INNER JOIN
    datalake_ebdb_listing.house  AS h
      ON h.id_region = fl.sk_region
  WHERE
    p.business_context = 'SALE'
    AND h.country_code != 'MX'
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY p.id_house ORDER BY p.rev DESC) = 1
),
sale_mdape AS (
  SELECT
    p.city_name,
    p.business_context,
    MEDIAN(p.percentual_error) AS mdape_city
  FROM
    sale_prices_errors AS p
  GROUP BY ALL
),
rent_mdape AS (
  SELECT
    dhl.house_city AS city_name,
    hpp.business_context,
    MEDIAN(ABS(100.0*dc.rent / p_50 - 100)) AS mdape_city
  FROM
    dw_rent.fact_listing_rent_flows AS rf
  INNER JOIN
    dw_public.dim_contract AS dc
      ON rf.sk_contract = dc.sk_contract
  INNER JOIN
    dw_public.dim_house_listing AS dhl
      ON dhl.sk_house_listing = rf.sk_house_listing
  INNER JOIN
    datalake_ebdb_clean.house_predicted_price AS hpp
      ON dhl.id_house = hpp.id_house
  WHERE
    DATEDIFF(CURRENT_DATE, dc.dt_start) <= 60
    AND hpp.business_context = 'RENT'
    AND dhl.country_code != 'MX'
  GROUP BY ALL
),
union_context AS (
  SELECT
    city_name,
    business_context,
    mdape_city
  FROM
    sale_mdape
  UNION
  SELECT
    city_name,
    business_context,
    mdape_city
  FROM
    rent_mdape
)
SELECT DISTINCT
  dr.sk_region AS id_region,
  uc.city_name,
  uc.business_context,
  ROUND(uc.mdape_city, 2) AS mdape_city
FROM
  union_context AS uc
INNER JOIN
  dw_public.dim_region AS dr
    ON uc.city_name = dr.city_name
