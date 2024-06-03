SELECT
  id_early_credit as sk_early_credit,
  id_credit_evaluation as sk_credit_evaluation,
  id_user as sk_user,
  id_house as sk_house,
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
  ts_created,
  ts_expired
FROM
  datalake_sorting_hat.early_credit_analysis
WHERE
  is_last_early_credit = TRUE
