WITH atento_tables AS (
  SELECT
    'backlog_metric' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_atento.backlog_metric
  GROUP BY 1

    UNION ALL

  SELECT
    'csat_front' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_atento.csat_front
  GROUP BY 1

    UNION ALL

  SELECT
    'demand_metric' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_atento.demand_metric
  GROUP BY 1

    UNION ALL

  SELECT
    'fcr_metric' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_atento.fcr_metric
  GROUP BY 1

    UNION ALL

  SELECT
    'general_metric' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_atento.general_metric
  GROUP BY 1

    UNION ALL

  SELECT
    'speech_call' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_atento.speech_call
  GROUP BY 1

    UNION ALL

  SELECT
    'speech_chat' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_atento.speech_chat
  GROUP BY 1

    UNION ALL

  SELECT
    'twilio_chat_aht' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_atento.twilio_chat_aht
  GROUP BY 1

    UNION ALL

  SELECT
    'recontact_mx' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_atento.recontact_mx
  GROUP BY 1

    UNION ALL

  SELECT
    'taxonomy' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_atento.taxonomy
  GROUP BY 1

    UNION ALL

  SELECT
    'tmr' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_atento.tmr
  GROUP BY 1

    UNION ALL

  SELECT
    'tickets_transferred' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_atento.tickets_transferred
  GROUP BY 1

    UNION ALL

  SELECT
    'email' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_atento.email
  GROUP BY 1

    UNION ALL

  SELECT
    'recontact' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_atento.recontact
  GROUP BY 1
)
SELECT
  'Atento' AS bpo,
  table_name,
  ts_load AS max_ts_load,
  YEAR(CURRENT_DATE) AS year,
  MONTH(CURRENT_DATE) AS month,
  DAY(CURRENT_DATE) AS day
FROM
  atento_tables
WHERE
  DATE(ts_load) = CURRENT_DATE

