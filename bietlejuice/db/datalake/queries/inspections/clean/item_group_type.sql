SELECT
    id AS id_item_group_type,
    type,
    deletable AS is_deletable,
    deleted AS is_deleted,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.item_group_type
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
