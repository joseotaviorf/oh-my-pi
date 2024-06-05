WITH
contracts AS (
  SELECT
    fhl.sk_house_listing,
    CASE 
      WHEN 
        dhl.rent <= 1500 THEN 'LOW'
      WHEN 
        dhl.rent < 2500 THEN 'MEDIUM'
      WHEN 
        dhl.rent >= 2500 THEN 'HIGH'
      ELSE 
        'UNDEFINED'
    END AS value_segment,
    COALESCE(fhl.sk_contract, fhl.sk_previous_contract) AS id_contract_listing
  FROM
    dw_rent.fact_house_listings AS fhl
  JOIN
    dw_rent.dim_house_listing AS dhl
      ON dhl.sk_house_listing = fhl.sk_house_listing
),
base_contract AS (
  SELECT
    c.sk_house_listing,
    c.id_contract_listing,
    COALESCE(dc.value_segment, c.value_segment) AS category
  FROM
    contracts AS c
  LEFT JOIN
    dw_rent.dim_contract AS dc
      ON dc.sk_contract = c.id_contract_listing
)
SELECT 
  CAST(DATE_TRUNC('WEEK', dhl.ts_publication) AS DATE) AS dt_week_publication,
  'OVERALL' AS category,
  dhl.country_code,
  COUNT(DISTINCT 
    IF(
      dhl.listing_category_start = 'Re-Listing' 
      AND dhl.is_early_demand IS TRUE
      , dhl.sk_house_listing
      , NULL
    )
  ) AS qtd_ed_rl, 
  COUNT(DISTINCT 
    IF(
      dhl.listing_category_start = 'Re-Listing'
      , dhl.sk_house_listing
      , NULL
    )
  ) AS qtd_rl,
  CAST(
    COUNT(DISTINCT 
      IF(
        dhl.listing_category_start = 'Re-Listing' 
        AND dhl.is_early_demand IS TRUE
        , dhl.sk_house_listing
        , NULL
      )
    ) AS DOUBLE
  ) 
  / 
  COUNT(DISTINCT 
    IF(
      dhl.listing_category_start = 'Re-Listing'
      , dhl.sk_house_listing
      , NULL
    )
  ) * 1.0 AS pct_ed_rl
FROM 
  dw_rent.dim_house_listing AS dhl
GROUP BY 
  1, 2, 3

UNION ALL

SELECT 
  CAST(DATE_TRUNC('WEEK', dhl.ts_publication) AS DATE) AS dt_week_publication,
  bc.category,
  dhl.country_code,
  COUNT(DISTINCT 
    IF(
      dhl.listing_category_start = 'Re-Listing' 
      AND dhl.is_early_demand IS TRUE
      , dhl.sk_house_listing
      , NULL
    )
  ) AS qtd_ed_rl, 
  COUNT(DISTINCT 
    IF(
      dhl.listing_category_start = 'Re-Listing'
      , dhl.sk_house_listing
      , NULL
    )
  ) AS qtd_rl,
  CAST(
    COUNT(DISTINCT 
      IF(
        dhl.listing_category_start = 'Re-Listing' 
        AND dhl.is_early_demand IS TRUE
        , dhl.sk_house_listing
        , NULL
      )
    ) AS DOUBLE
  ) 
  / 
  COUNT(DISTINCT 
    IF(
      dhl.listing_category_start = 'Re-Listing'
      , dhl.sk_house_listing
      , NULL
    )
  ) * 1.0 AS pct_ed_rl
FROM 
  dw_rent.dim_house_listing AS dhl
JOIN 
  base_contract AS bc
    ON bc.sk_house_listing  = dhl.sk_house_listing
GROUP BY 
  1, 2, 3