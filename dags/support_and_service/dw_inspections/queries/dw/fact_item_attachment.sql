SELECT DISTINCT
    MD5(CONCAT(im.id_item, im.id_item_media, "item_media")) AS sk_item_attachment,
    MD5(CONCAT(im.id_item_media, "item_media")) AS sk_item_media,
    im.id_item_media AS sk_origin_media,
    NULL AS sk_item_review,
    im.id_item AS sk_item,
    im.id_external_media AS sk_external_media,
    im.id_assessment AS sk_assessment,
    CAST(im.id_inspection AS STRING) AS sk_inspection,
    NULL AS sk_reviewer,
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
    im.id_item_media IS NOT NULL
    AND MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
UNION ALL
SELECT
    MD5(CONCAT(ir.id_item, ir.id_review, COALESCE(ir.id_review_media, ""), "review_media")) AS sk_item_attachment,
    MD5(CONCAT(ir.id_review_media, "review_media")) AS sk_item_media,
    ir.id_review_media AS sk_origin_media,
    ir.id_review AS sk_item_review,
    ir.id_item AS sk_item,
    ir.id_external_media AS sk_external_media,
    ir.id_assessment AS sk_assessment,
    CAST(ir.id_inspection AS STRING) AS sk_inspection,
    ir.id_reviewer AS sk_reviewer,
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
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')