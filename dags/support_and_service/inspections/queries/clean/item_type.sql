SELECT
    id AS id_item_type,
    item_group_type_id AS id_item_group_type,
    display_type,
    media_type,
    type,
    allow_comments,
    allow_media,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.item_type
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
