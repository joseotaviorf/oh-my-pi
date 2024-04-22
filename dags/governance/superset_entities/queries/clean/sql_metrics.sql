SELECT 
    id,
    table_id AS id_table,
    created_by_fk AS id_user_created,
    changed_by_fk AS id_user_changed,
    metric_name,
    verbose_name,
    metric_type,
    expression,
    description,
    d3format,
    warning_text,
    extra,
    uuid,
    currency,
    created_on AS ts_created,
    changed_on AS ts_changed,
    year,
    month,
    day
FROM datalake_superset_raw.sql_metrics
WHERE MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"