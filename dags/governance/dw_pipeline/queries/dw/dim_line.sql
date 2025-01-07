SELECT
    l.id_line AS sk_line,
    l.line_name,
    l.is_data_line,
    l.ts_line_first_event,
    NOW() AS ts_load
FROM
    datalake_pipeline.line AS l