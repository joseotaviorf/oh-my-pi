SELECT
    id AS id_item_issue,
    item_id AS id_item,
    type_id AS id_type,
    uuid,
    comment,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.item_issue
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}