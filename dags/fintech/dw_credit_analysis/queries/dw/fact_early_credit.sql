WITH dates as (
  SELECT
    id_user,
    id_house,
    MIN(CAST(ts_created AS DATE)) AS dt_min_early_credit_created,
    MAX(CAST(ts_expired AS DATE)) AS dt_max_early_credit_expired
  FROM 
    datalake_sorting_hat.early_credit_analysis
  GROUP BY 1,2
),
flrf AS (
SELECT 
  TO_DATE(flrf.sk_offer_submitted_date::STRING, 'yyyyMMdd')  AS dt_offer_submitted_date,
  flrf.sk_proposal,
  flrf.sk_offer,
  flrf.sk_client,
  CAST(flrf.sk_house_listing / 1000 AS INTEGER) AS sk_house
FROM 
  dw_rent.fact_listing_rent_flows  flrf
),
base_offer AS (
SELECT 
  flrf.sk_offer,
  flrf.dt_offer_submitted_date,
  flrf.sk_client,
  flrf.sk_house,
  ec.id_early_credit,
  ec.id_credit_evaluation,
  ec.id_user,
  ec.id_house,
  ec.id_variant,
  ec.version,
  ec.risk_category_canon,
  ec.bypass,
  ec.guarantee_offered,
  ec.category,
  ec.range_end,
  ec.range_start,
  ec.rejection_reason,
  ec.ts_created,
  ec.ts_expired
FROM 
   datalake_sorting_hat.early_credit_analysis ec
LEFT JOIN 
  flrf
  ON  flrf.sk_client = ec.id_user
  AND flrf.sk_house  = ec.id_house
  AND flrf.dt_offer_submitted_date 
    BETWEEN cast(ec.ts_created AS DATE) - INTERVAL '1' MONTH AND cast(ec.ts_created AS DATE)
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY sk_offer ORDER BY ts_created DESC) = 1
), offer AS (
SELECT 
  sk_offer,
  dt_offer_submitted_date,
  id_early_credit,
  id_credit_evaluation,
  id_user,
  id_house,
  id_variant,
  version,
  risk_category_canon,
  bypass,
  guarantee_offered,
  category,
  range_end,
  range_start,
  rejection_reason,
  ts_created,
  ts_expired
FROM
  base_offer
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY id_user, id_house ORDER BY ts_created DESC) = 1
)
SELECT
  ec.id_early_credit AS sk_early_credit_analysis,
  offer.sk_offer,
  ec.id_credit_evaluation AS sk_credit_evaluation,
  ec.id_user AS sk_user,
  ec.id_house AS sk_house,
  ec.id_variant,
  ec.city,
  ec.version,
  ec.risk_category_canon,
  ec.bypass,
  ec.guarantee_offered,
  ec.category,
  ec.range_end,
  ec.range_start,
  ec.rejection_reason,
  CAST(ec.ts_created AS DATE) AS dt_early_credit_created,
  CAST(ec.ts_expired AS DATE) AS dt_early_credit_expired,
  dates.dt_min_early_credit_created,
  dates.dt_max_early_credit_expired
FROM
  datalake_sorting_hat.early_credit_analysis ec
LEFT JOIN dates 
  ON  ec.id_user = dates.id_user
  AND ec.id_house = dates.id_house
LEFT JOIN offer
  ON  ec.id_user = offer.id_user
  AND ec.id_house = offer.id_house
WHERE
  is_last_early_credit = TRUE
