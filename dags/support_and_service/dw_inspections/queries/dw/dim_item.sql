SELECT
    i.id_item AS sk_item,
    i.item_type,
    i.media_type AS item_media_type,
    i.comment As item_comment,
    i.status AS item_status,
    i.ts_created,
    i.ts_updated,
    NOW() AS ts_load,
    i.year,
    i.month,
    i.day
FROM
    datalake_inspections.item i
WHERE
    i.year = {year}
    AND i.month = {month}
    AND i.day = {day}
