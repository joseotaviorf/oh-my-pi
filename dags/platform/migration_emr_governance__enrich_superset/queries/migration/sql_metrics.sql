WITH metrics AS (
    SELECT 
    *,
    RANK() OVER (PARTITION BY id ORDER BY ts_changed DESC) most_recent_rank
    FROM datalake_superset_clean.sql_metrics
)
SELECT 
    id,
    id_table,
    id_user_created,
    id_user_changed,
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
    ts_created,
    ts_changed,
    year,
    month,
    day
FROM metrics
WHERE most_recent_rank = 1