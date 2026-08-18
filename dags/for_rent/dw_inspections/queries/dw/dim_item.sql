WITH ranked_item AS (
    SELECT
        i.id_item AS sk_item,
        i.item_type,
        i.media_type AS item_media_type,
        i.comment AS item_comment,
        i.ts_created,
        i.ts_updated,
        i.year,
        i.month,
        i.day,
        ROW_NUMBER() OVER (PARTITION BY i.id_item ORDER BY i.ts_updated DESC) AS rn
    FROM
        datalake_inspections.item AS i
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    sk_item,
    item_type,
    item_media_type,
    item_comment,
    ts_created,
    ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    ranked_item
WHERE
    rn = 1
