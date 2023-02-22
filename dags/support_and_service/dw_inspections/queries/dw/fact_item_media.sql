SELECT DISTINCT
    MD5(CONCAT(im.id_item_media, im.user_type, im.ts_updated)) AS sk_item_media,
    NULL AS sk_review,
    im.id_item AS sk_item,
    im.id_external_media AS sk_external_media,
    im.id_assessment AS sk_assessment,
    im.id_inspection AS sk_inspection,
    im.id_user AS sk_user,
    FALSE AS is_review_media,
    im.ts_created,
    im.ts_updated,
    NOW() AS ts_load,
    im.year,
    im.month,
    im.day
FROM
    datalake_inspections.item_media im
WHERE
    im.year = {year}
    AND im.month = {month}
    AND im.day = {day}
UNION ALL
SELECT
    MD5(CONCAT(ir.id_review_media, ir.user_type, ir.ts_updated)) AS sk_item_media,
    ir.id_review AS sk_review,
    ir.id_item AS sk_item,
    ir.id_external_media AS sk_external_media,
    ir.id_assessment AS sk_assessment,
    ir.id_inspection AS sk_inspection,
    ir.id_user AS sk_user,
    TRUE AS is_review_media,
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