SELECT
    'Atento' AS reverse_context,
    table_name,
    ts_last_modified,
    ts_execution
FROM
    reverse_atento.atento_execution_tracking
UNION ALL
SELECT
    'Webhelp' AS reverse_context,
    table_name,
    CAST(dt_last_updated AS TIMESTAMP) AS ts_last_modified,
    ts_execution
FROM
    reverse_webhelp.webhelp_execution_tracking
