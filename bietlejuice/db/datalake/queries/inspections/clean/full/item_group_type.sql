SELECT
    id,
    type,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_inspections_raw.item_group_type