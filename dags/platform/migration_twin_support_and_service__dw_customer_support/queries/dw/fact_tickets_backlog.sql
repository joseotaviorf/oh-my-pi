SELECT
  CAST(id_ticket AS BIGINT) AS sk_ticket,
  MD5(
    CONCAT(
      COALESCE(step_tag, 'step_tag'),
      COALESCE(customer_type_tag, 'customer_type_tag'),
      COALESCE(client_type, 'client_type'),
      COALESCE(request_type, 'request_type'),
      COALESCE(contact_motivation_tag, 'contact_motivation_tag'),
      COALESCE(contact_theme_tag, 'contact_theme_tag'),
      COALESCE(contact_theme_detail_tag, 'contact_theme_detail_tag')
    )
  ) AS sk_taxonomy, 
  MD5(last_analyst_email) AS sk_analyst,
  MD5(last_queue) AS sk_department,
  sla_target,
  days_off,
  days_elapsed_business,
  days_elapsed_calendar,
  CASE
    WHEN days_elapsed_business <= sla_target THEN TRUE
    ELSE FALSE
  END AS is_backlog_within_sla,
  CASE
    WHEN days_elapsed_business > sla_target THEN TRUE
    ELSE FALSE
  END AS is_backlog_outside_sla,
  DATE("{load_start_date}") AS dt_snapshot,
  ts_created,
  ts_sla_started,
  ts_budget,
  NOW() AS ts_load
FROM
  datalake_customer_support.tickets
WHERE
  channel = 'email'
  AND ts_solved IS NULL
  AND "{load_start_date}" >= DATE(ts_sla_started)
  AND "{load_start_date}" >= COALESCE(ts_solved, DATE("1900-01-01")) -- only select tickets with no ts_solved
  AND (
    last_queue <> 'Offboarding Reparos [OFF] [POS] [BACK]'
    OR (
      last_queue = 'Offboarding Reparos [OFF] [POS] [BACK]'
      AND tags LIKE '%orçamentação_realizada%'
    )
  )
