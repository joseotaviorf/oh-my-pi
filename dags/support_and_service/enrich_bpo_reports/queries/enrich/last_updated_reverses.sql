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
        'taxonomia_call' AS table_name,
        ts_load
    FROM
        reverse_atento.taxonomia_call
    UNION ALL
    SELECT
        'taxonomia_chat' AS table_name,
        ts_load
    FROM
        reverse_atento.taxonomia_chat
    UNION ALL
    SELECT
        'taxonomia_email' AS table_name,
        ts_load
    FROM
        reverse_atento.taxonomia_email
    UNION ALL
    SELECT
        'twilio_chat_aht' AS table_name,
        ts_load
    FROM
        reverse_atento.twilio_chat_aht
),
webhelp_tables AS (
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
        reverse_webhelp.taxonomia_call
    UNION ALL
    SELECT
        'taxonomia_chat' AS table_name,
        ts_load
    FROM
        reverse_webhelp.taxonomia_chat
    UNION ALL
    SELECT
        'taxonomia_email' AS table_name,
        ts_load
    FROM
        reverse_webhelp.taxonomia_email
    UNION ALL
    SELECT
        'twilio_chat_aht' AS table_name,
        ts_load
    FROM
        reverse_webhelp.twilio_chat_aht
)
SELECT DISTINCT
    'Atento' AS bpo,
    table_name,
    ts_load   
FROM
    atento_tables
UNION ALL
SELECT DISTINCT
    'Webhelp' AS bpo,
    table_name,
    ts_load   
FROM
    webhelp_tables
