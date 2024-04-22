WITH objects AS (
    SELECT 
    *,
    RANK() OVER (PARTITION BY id ORDER BY ts_changed DESC) most_recent_rank
    FROM datalake_superset_clean.tagged_object
)
SELECT
    id,
    id_tag,
    id_object,
    id_user_created,
    id_user_changed,
    object_type,
    ts_created,
    ts_changed,
    year,
    month,
    day
FROM objects
WHERE most_recent_rank = 1