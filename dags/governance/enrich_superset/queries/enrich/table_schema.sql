WITH schemas AS (
    SELECT 
    *,
    RANK() OVER (PARTITION BY id ORDER BY ts_changed DESC) most_recent_rank
    FROM datalake_superset_clean.table_schema
)
SELECT 
    id,
    id_user_created,
    id_user_changed,
    id_tab_state,
    id_database,
    extra_json,
    schema,
    table,
    description,
    expanded,
    ts_created,
    ts_changed,
    year,
    month,
    day
FROM schemas
WHERE most_recent_rank = 1