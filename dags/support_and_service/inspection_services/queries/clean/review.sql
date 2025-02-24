SELECT
    id AS id_review,
    item_id AS id_item,
    user_id AS id_user,
    reviewer_id AS id_reviewer,
    user_type,
    comment,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.review
