SELECT
  TO_DATE(initial_dt_month_reference, 'yyyy-MM-dd') AS initial_dt_month_reference,
  TO_DATE(last_dt_month_reference, 'yyyy-MM-dd') AS last_dt_month_reference,
  TO_DATE(initial_dt_start_reference, 'yyyy-MM-dd') AS initial_dt_start_reference,
  TO_DATE(last_dt_start_reference, 'yyyy-MM-dd') AS last_dt_start_reference,
  IF(LOWER(TRIM(is_guarantee_paid)) = 'true', TRUE, FALSE) AS is_guarantee_paid,
  CAST(NULLIF(TRIM(delay_range_start), '') AS INT) AS delay_range_start,
  CAST(NULLIF(TRIM(delay_range_end), '') AS INT) AS delay_range_end,
  CAST(NULLIF(TRIM(exposure_at_default), '') AS DOUBLE) AS exposure_at_default,
  CAST(NULLIF(TRIM(loss_given_default), '') AS DOUBLE) AS loss_given_default,
  NULLIF(TRIM(ead_lgd_model_version), '') AS ead_lgd_model_version
FROM
  datalake_gsheets_raw.ead_lgd_liability
