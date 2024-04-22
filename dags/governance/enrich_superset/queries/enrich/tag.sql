WITH tags AS (
    SELECT 
    *,
    RANK() OVER (PARTITION BY id ORDER BY ts_changed DESC) most_recent_rank
    FROM datalake_superset_clean.tag
)
SELECT 
    id,
    id_user_created,
    id_user_changed,
    tag_name,
    type,
    description,
    ts_created,
    ts_changed,
    year,
    month,
    day
FROM tags
WHERE most_recent_rank = 1