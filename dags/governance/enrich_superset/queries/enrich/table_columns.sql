WITH columns AS (
    SELECT 
    *,
    RANK() OVER (PARTITION BY id ORDER BY ts_changed DESC) most_recent_rank
    FROM datalake_superset_clean.table_columns
)
SELECT 
    id,
    id_table,
    id_user_created,
    id_user_changed,
    column_name,
    type,
    groupby,
    filterable,
    description,
    expression,
    verbose_name,
    python_date_format,
    uuid,
    extra,
    advanced_data_type,
    is_dttm,
    is_active,
    ts_created,
    ts_changed,
    year,
    month,
    day
FROM columns
WHERE most_recent_rank = 1