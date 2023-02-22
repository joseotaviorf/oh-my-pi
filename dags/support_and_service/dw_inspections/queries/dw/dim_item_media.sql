SELECT DISTINCT
    MD5(CONCAT(im.id_item_media, im.user_type, im.ts_updated)) AS sk_item_media,
    im.user_type AS media_creator,
    im.media_type,
    im.media_path,
    im.ts_created,
    im.ts_updated,
    NOW() AS ts_load,
    im.year,
    im.month,
    im.day
FROM
    datalake_inspections.item_media AS im
WHERE
    im.year = {year}
    AND im.month = {month}
    AND im.day = {day}
UNION ALL
SELECT
    MD5(CONCAT(ir.id_review_media, ir.user_type, ir.ts_updated)) AS sk_item_media,
    ir.user_type AS media_creator,
    ir.media_type,
    ir.media_path,
    ir.ts_media_created AS ts_created,
    ir.ts_media_updated AS ts_updated,
    NOW() AS ts_load,
    ir.year,
    ir.month,
    ir.day
FROM
    datalake_inspections.item_review AS ir
WHERE
    ir.year = {year}
    AND ir.month = {month}
    AND ir.day = {day}