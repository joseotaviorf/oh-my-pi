WITH item_group_type_ranked AS (
    SELECT
        igt.id_item_group_type,
        igt.type AS item_group_type,
        -- RANK, not ROW_NUMBER: the original ts_updated = FIRST(ts_updated) OVER (...)
        -- kept every row tied on the latest ts_updated.
        RANK() OVER (PARTITION BY igt.id_item_group_type ORDER BY igt.ts_updated DESC) AS rn
    FROM
        datalake_inspection_services_clean.item_group_type igt
),
item_group_type AS (
    SELECT
        id_item_group_type,
        item_group_type
    FROM
        item_group_type_ranked
    WHERE
        rn = 1
),
item_group_ranked AS (
    SELECT
        ig.id_item_group,
        igt.id_item_group_type,
        ig.id_room,
        ig.id_main,
        ig.name AS item_group_name,
        igt.item_group_type,
        ig.status,
        ig.is_inferior_quality,
        ig.is_active_status,
        ig.is_active_inferior_quality,
        ig.ts_created,
        ig.ts_updated,
        ig.year,
        ig.month,
        ig.day,
        ROW_NUMBER() OVER (PARTITION BY ig.id_item_group ORDER BY ig.ts_updated DESC) AS rn
    FROM
        datalake_inspection_services_clean.item_group AS ig
    JOIN
        item_group_type AS igt
            ON ig.id_type = igt.id_item_group_type
    WHERE
        MAKE_DATE(ig.year, ig.month, ig.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    id_item_group,
    id_item_group_type,
    id_room,
    id_main,
    item_group_name,
    item_group_type,
    status,
    is_inferior_quality,
    is_active_status,
    is_active_inferior_quality,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    item_group_ranked
WHERE
    rn = 1
