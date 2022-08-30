SELECT
    id AS id_review,
    item_id AS id_item,
    user_id AS id_user,
    user_type,
    comment,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.review
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}