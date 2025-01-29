CREATE OR REPLACE TEMPORARY VIEW vw_last_updated_webhelp AS
WITH webhelp_tables AS (
  SELECT
    'backlog_metric' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_webhelp.backlog_metric
  GROUP BY 1

    UNION ALL

  SELECT
    'csat_front' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_webhelp.csat_front
  GROUP BY 1

    UNION ALL

  SELECT
    'demand_metric' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_webhelp.demand_metric
  GROUP BY 1

    UNION ALL

  SELECT
    'fcr_metric' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_webhelp.fcr_metric
  GROUP BY 1

    UNION ALL

  SELECT
    'general_metric' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_webhelp.general_metric
  GROUP BY 1

    UNION ALL

  SELECT
    'listing_quality_sla' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_webhelp.listing_quality_sla
  GROUP BY 1

    UNION ALL

  SELECT
    'listing_quality_tasks' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_webhelp.listing_quality_tasks
  GROUP BY 1

    UNION ALL

  SELECT
    'repair_tickets' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_webhelp.repair_tickets
  GROUP BY 1

    UNION ALL

  SELECT
    'speech_call' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_webhelp.speech_call
  GROUP BY 1

    UNION ALL

  SELECT
    'speech_chat' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_webhelp.speech_chat
  GROUP BY 1

    UNION ALL

  SELECT
    'taxonomia_call' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_webhelp.taxonomy
  GROUP BY 1

    UNION ALL

  SELECT
    'twilio_chat_aht' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_webhelp.twilio_chat_aht
  GROUP BY 1

    UNION ALL

  SELECT
    'recontact' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_webhelp.recontact
  GROUP BY 1

    UNION ALL

  SELECT
    'tickets_transferred' AS table_name,
    MAX(MAKE_DATE(year, month, day)) AS ts_load
  FROM
    reverse_webhelp.tickets_transferred
  GROUP BY 1
)

SELECT DISTINCT
  'webhelp' AS bpo,
  table_name,
  ts_load,
  YEAR(CURRENT_DATE) AS year,
  MONTH(CURRENT_DATE) AS month,
  DAY(CURRENT_DATE) AS day
FROM
  webhelp_tables
WHERE
  DATE(ts_load) = CURRENT_DATE - 1
