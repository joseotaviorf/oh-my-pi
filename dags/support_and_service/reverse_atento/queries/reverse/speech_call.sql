SELECT DISTINCT
  bc.id_source_unique,
  bc.caller_phone_number,
  bc.destination_phone_number,
  c.direction,
  bc.provider,
  c.agent_email,
  c.country_code,
  bc.recording_url,
  bc.ts_started,
  bc.ts_ended,
  YEAR(CURRENT_DATE) AS year,
  MONTH(CURRENT_DATE) AS month,
  DAY(CURRENT_DATE) AS day,
  NOW() AS ts_load
FROM
  datalake_bigfone_clean.call AS bc
LEFT JOIN
  datalake_customer_support.call AS c
    ON bc.id_source_unique = c.sk_call
LEFT JOIN
  datalake_support_users.analysts AS a
    ON c.agent_email = a.email
WHERE
  a.organization IN ('atento', 'atn')
  AND DATE(bc.ts_started) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
