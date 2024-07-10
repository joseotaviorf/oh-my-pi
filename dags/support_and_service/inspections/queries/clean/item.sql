SELECT
    id AS id_item,
    item_group_id AS id_item_group,
    previous_item_id AS id_previous_item,
    type_id AS id_type,
    main_id AS id_main,
    uuid,
    comment,
    count,
    status,
    present AS is_present,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.item
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}