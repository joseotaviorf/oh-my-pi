SELECT
  id_user,
  scoring_date AS dt_scored,
  score,
  effective_score,
  suppression_threshold,
  is_eligibility_bypass,
  is_suppressed,
  model_version,
  year,
  month,
  day
FROM
  datalake_concierge_propensity_model_service_raw.concierge_propensity_scores
WHERE MAKE_DATE(year, month, day) = DATE('{load_start_date}')
