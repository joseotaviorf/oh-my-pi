SELECT
    id AS id_item_group_specification,
    item_group_type_id AS id_item_group_type,
    name,
    position,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspection_services_raw.item_group_specification
