WITH dates as (
  SELECT
    id_user,
    id_house,
    MIN(CAST(ts_created AS DATE)) AS dt_min_early_credit_created,
    MAX(CAST(ts_expired AS DATE)) AS dt_max_early_credit_expired
  FROM 
    datalake_sorting_hat.early_credit_analysis
  GROUP BY 1,2
)
SELECT
  id_early_credit AS sk_early_credit_analysis,
  id_credit_evaluation AS sk_credit_evaluation,
  ec.id_user AS sk_user,
  ec.id_house AS sk_house,
  id_variant,
  city,
  version,
  risk_category_canon,
  bypass,
  guarantee_offered,
  category,
  range_end,
  range_start,
  rejection_reason,
  CAST(ts_created AS DATE) AS dt_early_credit_created,
  CAST(ts_expired AS DATE) AS dt_early_credit_expired,
  dates.dt_min_early_credit_created,
  dates.dt_max_early_credit_expired
FROM
  datalake_sorting_hat.early_credit_analysis ec
LEFT JOIN dates 
  ON  ec.id_user = dates.id_user
  AND ec.id_house = dates.id_house
WHERE
  is_last_early_credit = TRUE
