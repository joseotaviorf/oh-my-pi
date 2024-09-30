WITH atento_tables AS (
  SELECT
    'backlog_metric' AS table_name,
    ts_load
  FROM
      reverse_atento.backlog_metric
  
    UNION ALL
  
  SELECT
    'csat_front' AS table_name,
    ts_load
  FROM
      reverse_atento.csat_front
  
    UNION ALL
  
  SELECT
    'demand_metric' AS table_name,
    ts_load
  FROM
      reverse_atento.demand_metric
  
    UNION ALL
  
  SELECT
    'fcr_metric' AS table_name,
    ts_load
  FROM
      reverse_atento.fcr_metric
  
    UNION ALL
  
  SELECT
    'general_metric' AS table_name,
    ts_load
  FROM
      reverse_atento.general_metric
  
    UNION ALL
  
  SELECT
    'speech_call' AS table_name,
    ts_load
  FROM
      reverse_atento.speech_call
  
    UNION ALL
  
  SELECT
    'speech_chat' AS table_name,
    ts_load
  FROM
      reverse_atento.speech_chat
  
    UNION ALL
  
  SELECT
    'twilio_chat_aht' AS table_name,
    ts_load
  FROM
      reverse_atento.twilio_chat_aht
  
    UNION ALL
  
  SELECT
    'recontact_mx' AS table_name,
    ts_load
  FROM
      reverse_atento.recontact_mx
  
    UNION ALL
  
  SELECT
    'taxonomy' AS table_name,
    ts_load
  FROM
      reverse_atento.taxonomy
  
    UNION ALL
  
  SELECT
    'tmr' AS table_name,
    ts_load
  FROM
      reverse_atento.tmr
  
    UNION ALL
  
  SELECT
    'tickets_transferred' AS table_name,
    ts_load
  FROM reverse_atento.tickets_transferred
  
    UNION ALL
  
  SELECT
    'email' AS table_name,
    ts_load
  FROM reverse_atento.email
  
    UNION ALL
  
  SELECT
    'recontact' AS table_name,
    ts_load
  FROM reverse_atento.recontact
)
SELECT DISTINCT
  'Atento' AS bpo,
  table_name,
  ts_load
FROM
  atento_tables
