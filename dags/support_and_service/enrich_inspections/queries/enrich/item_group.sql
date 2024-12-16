WITH item_group_type AS (
    SELECT
        igt.id_item_group_type,
        igt.type AS item_group_type
    FROM
        datalake_inspections_clean.item_group_type igt
    QUALIFY
        igt.ts_updated = FIRST(igt.ts_updated) OVER(PARTITION BY igt.id_item_group_type ORDER BY igt.ts_updated DESC)
)
SELECT
    ig.id_item_group,
    igt.id_item_group_type,
    ig.id_room,
    ig.id_main,
    ig.name AS item_group_name,
    igt.item_group_type,
    ig.status,
    ig.is_inferior_quality,
    ig.ts_created,
    ig.ts_updated,
    ig.year,
    ig.month,
    ig.day
FROM
    datalake_inspections_clean.item_group AS ig
JOIN
    item_group_type AS igt
        ON ig.id_type = igt.id_item_group_type
WHERE
    MAKE_DATE(ig.year, ig.month, ig.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY ig.id_item_group ORDER BY ig.ts_updated DESC) = 1
