SELECT
    id AS id_review_media,
    review_id As id_review,
    main_id AS id_main,
    uuid,
    type,
    path,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.review_media
