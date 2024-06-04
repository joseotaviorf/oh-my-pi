WITH base_pro_owners AS (
  SELECT DISTINCT
    dd.date,
    id_owner
  FROM datalake_pro_owners.owner_houses_quantity_history AS po
  INNER JOIN dw_public.dim_date AS dd
    ON dd.date BETWEEN DATE(po.ts_house_number_started) AND COALESCE(DATE(po.ts_house_number_ended), DATE_ADD(CURRENT_DATE, -1))
  WHERE
    houses >= 5
), base_oportunidade AS (
  SELECT DISTINCT
    dd.date,
    id_owner
  FROM datalake_pro_owners.owner_houses_quantity_history AS opp
  INNER JOIN dw_public.dim_date AS dd
    ON dd.date BETWEEN DATE(opp.ts_house_number_started) AND COALESCE(DATE(opp.ts_house_number_ended), DATE_ADD(CURRENT_DATE, -1))
  WHERE
    houses BETWEEN 3 AND 4
)
SELECT DISTINCT
  dd.date AS dt_first_listing,
  fhlf.sk_house_listing,
  CAST(fhlf.sk_house_listing / 1000 AS INT) AS id_house,
  fhl.sk_owner,
  CASE
    WHEN NOT bpo.id_owner IS NULL
    THEN 'Pro Owner'
    WHEN NOT bopp.id_owner IS NULL
    THEN 'Oportunidade'
    ELSE 'Amador'
  END AS category
FROM dw_public.fact_house_listing_flows AS fhlf
INNER JOIN dw_public.dim_date AS dd
  ON dd.sk_date = fhlf.sk_first_listing_date
LEFT JOIN dw_rent.fact_house_listings AS fhl
  ON CAST(fhlf.sk_house_listing / 1000 AS INT) = CAST(fhl.sk_house_listing / 1000 AS INT)
LEFT JOIN base_pro_owners AS bpo
  ON bpo.id_owner = fhl.sk_owner AND dd.date = bpo.date
LEFT JOIN base_oportunidade AS bopp
  ON bopp.id_owner = fhl.sk_owner AND dd.date = bopp.date
WHERE
  fhlf.sk_first_listing_date > 0