WITH base_offer AS (
SELECT
  TO_DATE(CAST(flrf.sk_offer_submitted_date AS STRING), 'yyyyMMdd')  AS dt_offer_submitted_date,
  flrf.sk_proposal,
  flrf.sk_offer,
  flrf.sk_client,
  CAST(flrf.sk_house_listing / 1000 AS INTEGER) AS sk_house
FROM
  dw_rent.fact_listing_rent_flows  flrf
),
ec AS (
SELECT
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
), final_flow as (
SELECT
  a.sk_offer,
  a.dt_offer_submitted_date,
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
  base_offer a
INNER JOIN
  ec
  ON  a.sk_client = ec.id_user
  AND a.sk_house  = ec.id_house
  AND a.dt_offer_submitted_date
    BETWEEN cast(ec.ts_created AS DATE) AND cast(ec.ts_created AS DATE) + INTERVAL '1' MONTH
), ranked_flow as (
SELECT
  sk_offer,
  id_early_credit AS sk_early_credit_analysis,
  id_credit_evaluation AS sk_credit_evaluation,
  id_user AS sk_client,
  id_house AS sk_house,
  id_variant,
  version,
  risk_category_canon,
  bypass,
  guarantee_offered,
  category,
  range_start,
  range_end,
  rejection_reason,
  ts_created AS dt_early_credit_created,
  ts_expired AS dt_early_credit_expired,
  NOW() AS ts_load,
  ROW_NUMBER() OVER (PARTITION BY sk_offer ORDER BY ts_created DESC) AS rn
FROM
  final_flow
)
SELECT
  sk_offer,
  sk_early_credit_analysis,
  sk_credit_evaluation,
  sk_client,
  sk_house,
  id_variant,
  version,
  risk_category_canon,
  bypass,
  guarantee_offered,
  category,
  range_start,
  range_end,
  rejection_reason,
  dt_early_credit_created,
  dt_early_credit_expired,
  ts_load
FROM
  ranked_flow
WHERE
  rn = 1
