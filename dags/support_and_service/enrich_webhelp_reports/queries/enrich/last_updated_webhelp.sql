WITH webhelp_tables AS (
  SELECT
    'backlog_metric' AS table_name,
    ts_load
  FROM
    reverse_webhelp.backlog_metric
  
    UNION ALL
  
  SELECT
    'csat_front' AS table_name,
    ts_load
  FROM
    reverse_webhelp.csat_front
  
    UNION ALL
  
  SELECT
    'demand_metric' AS table_name,
    ts_load
  FROM
    reverse_webhelp.demand_metric
  
    UNION ALL
  
  SELECT
    'fcr_metric' AS table_name,
    ts_load
  FROM
    reverse_webhelp.fcr_metric
  
    UNION ALL
  
  SELECT
    'general_metric' AS table_name,
    ts_load
  FROM
    reverse_webhelp.general_metric
  
    UNION ALL
  
  SELECT
    'listing_quality_sla' AS table_name,
    ts_load
  FROM
    reverse_webhelp.listing_quality_sla
  
    UNION ALL
  
  SELECT
    'listing_quality_tasks' AS table_name,
    ts_load
  FROM
    reverse_webhelp.listing_quality_tasks
  
    UNION ALL
  
  SELECT
    'repair_tickets' AS table_name,
    ts_load
  FROM
    reverse_webhelp.repair_tickets
  
    UNION ALL
  
  SELECT
    'speech_call' AS table_name,
    ts_load
  FROM
    reverse_webhelp.speech_call
  
    UNION ALL
  
  SELECT
    'speech_chat' AS table_name,
    ts_load
  FROM
    reverse_webhelp.speech_chat
  
    UNION ALL
  
  SELECT
    'taxonomia_call' AS table_name,
    ts_load
  FROM
    reverse_webhelp.taxonomy
  
    UNION ALL
  
  SELECT
    'twilio_chat_aht' AS table_name,
    ts_load
  FROM
    reverse_webhelp.twilio_chat_aht
  
    UNION ALL
  
  SELECT
    'recontact' AS table_name,
    ts_load
  FROM
    reverse_webhelp.recontact
  
    UNION ALL
  
  SELECT
    'tickets_transferred' AS table_name,
    ts_load
  FROM
    reverse_webhelp.tickets_transferred
)
SELECT DISTINCT
  'Webhelp' AS bpo,
  table_name,
  ts_load
FROM
  webhelp_tables
