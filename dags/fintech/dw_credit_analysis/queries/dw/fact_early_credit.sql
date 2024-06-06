SELECT
  id_early_credit AS sk_early_credit_analysis,
  id_credit_evaluation AS sk_credit_evaluation,
  id_user AS sk_user,
  id_house AS sk_house,
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
  CAST(ts_expired AS DATE) AS dt_early_credit_expired
FROM
  datalake_sorting_hat.early_credit_analysis
WHERE
  is_last_early_credit = TRUE
