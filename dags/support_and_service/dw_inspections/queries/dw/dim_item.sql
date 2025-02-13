SELECT
    i.id_item AS sk_item,
    i.item_type,
    i.media_type AS item_media_type,
    i.comment As item_comment,
    i.ts_created,
    i.ts_updated,
    NOW() AS ts_load,
    i.year,
    i.month,
    i.day
FROM
    datalake_inspections.item i
WHERE
    is_present = TRUE
    AND MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_item ORDER BY ts_updated DESC) = 1
