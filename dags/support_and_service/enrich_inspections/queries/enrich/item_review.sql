SELECT
    r.id_review,
    rm.id_review_media,
    r.id_item,
    rm.id_main AS id_external_media,
    r.id_user,
    r.id_reviewer,
    i.id_assessment,
    i.id_inspection,
    rm.uuid AS uuid_media,
    r.user_type,
    CASE
        WHEN r.comment = '' THEN NULL
        ELSE r.comment
    END AS user_comment,
    rm.type AS media_type,
    rm.path AS media_path,
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
JOIN
    datalake_inspections.item i
        ON i.id_item = r.id_item
WHERE
    MAKE_DATE(r.year, r.month, r.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
