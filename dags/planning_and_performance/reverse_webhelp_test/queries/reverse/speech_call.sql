SELECT DISTINCT
  COALESCE(c.id_call, c.id_task) AS id_source_unique,
  c.from_phone_number AS caller_phone_number,
  c.to_phone_number AS destination_phone_number,
  c.direction,
  'twilio' AS provider,
  c.worker_email AS agent_email,
  'BR' AS country_code,
  bc.recording_url,
  bc.ts_started,
  bc.ts_ended,
  YEAR(CURRENT_DATE - 1) AS year,
  MONTH(CURRENT_DATE - 1) AS month,
  DAY(CURRENT_DATE - 1) AS day,
  NOW() AS ts_load
FROM
  datalake_customer_support.calls AS c
LEFT JOIN
  datalake_bigfone_clean.call AS bc
    ON bc.id_source_unique = COALESCE(c.id_call, c.id_task)
LEFT JOIN
  datalake_support_users.analysts AS a
    ON c.worker_email = a.email
WHERE
  a.organization IN ('webhelp', 'webhelpbr')
  AND DATE(bc.ts_started) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
