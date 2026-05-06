SELECT
  id_langfuse_session,
  first_queue,
  last_queue,
  offboarding_category,
  reasoning,
  is_offboarding,
  is_escalated,
  session_date AS dt_session,
  ts_load,
  year,
  month,
  day
FROM
  datalake_offboarding_categorization_raw.categorization
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
