SELECT
    id AS id_item_group_type,
    type,
    review_instruction,
    deletable AS is_deletable,
    deleted AS is_deleted,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspection_services_raw.item_group_type
