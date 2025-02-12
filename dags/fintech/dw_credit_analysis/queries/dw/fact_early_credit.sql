SELECT
  id_early_credit AS sk_early_credit_analysis,
  id_credit_evaluation AS sk_credit_evaluation,
  id_user AS sk_client,
  id_house AS sk_house,
  id_variant,
  city,
  version,
  risk_category_canon,
  bypass,
  guarantee_offered,
  category,
  range_start,
  range_end,
  rejection_reason,
  CAST(ts_created AS DATE) AS dt_early_credit_created,
  CAST(ts_expired AS DATE) AS dt_early_credit_expired,
  NOW() AS ts_load
FROM
  datalake_sorting_hat.early_credit_analysis ec
WHERE
  is_last_early_credit = TRUE
