
SELECT
    r.id_item,
    CASE
        WHEN r.comment IS NULL THEN NULL
        ELSE MD5(CONCAT(r.id_item, r.user_type, r.ts_created))
    END AS id_comment,
    CASE
        WHEN rm.id_review_media IS NULL THEN NULL
        ELSE MD5(CONCAT(rm.id_review_media, r.user_type))
    END AS id_media,
    rm.id_review_media AS id_source_media,
    r.id_review,
    rm.id_main,
    r.id_user,
    r.user_type,
    r.comment AS user_comment,
    rm.type AS media_type,
    rm.path AS media_path,
    TRUE AS is_review,
    rm.ts_created AS ts_media_created,
    rm.ts_updated AS ts_media_updated,
    r.ts_created,
    r.ts_updated,
    r.year,
    r.month,
    r.day
FROM
    datalake_inspections_clean.review r
LEFT JOIN
    datalake_inspections_clean.review_media rm
        ON rm.id_review = r.id_review
WHERE
    (
        r.comment IS NOT NULL
        OR rm.id_review_media IS NOT NULL
    )
    AND (
        rm.ts_updated = DATE('{year}-{month}-{day}')
        OR r.ts_updated = DATE('{year}-{month}-{day}')
    )
UNION ALL
SELECT
    im.id_item,
    CASE
        WHEN i.comment IS NULL THEN NULL
        ELSE MD5(CONCAT(i.id_item, "INSPECTOR", i.ts_created))
    END AS id_comment,
    CASE
        WHEN im.id_item_media IS NULL THEN NULL
        ELSE MD5(CONCAT(im.id_item_media, "INSPECTOR"))
    END AS id_media,
    im.id_item_media AS id_source_media,
    NULL AS id_review,
    im.id_main,
    NULL AS id_user, --TRAZER ID DO VISTORIADOR
    "INSPECTOR" AS user_type,
    i.comment AS user_comment,
    im.type AS media_type,
    im.url AS media_path,
    FALSE AS is_review,
    im.ts_created AS ts_media_created,
    im.ts_updated AS ts_media_updated,
    i.ts_created,
    i.ts_updated,
    i.year,
    i.month,
    i.day
FROM
    datalake_inspections.item i
LEFT JOIN
    datalake_inspections_clean.item_media im
        ON im.id_item = i.id_item
WHERE
    (
        i.comment IS NOT NULL
        OR im.id_item_media IS NOT NULL
    )
    AND (
        im.ts_updated = DATE('{year}-{month}-{day}')
        OR i.ts_updated = DATE('{year}-{month}-{day}')
    )
