SELECT
    id AS id_room_type,
    type,
    order AS number_order,
    deletable AS is_deletable,
    deleted AS is_deleted,
    is_default,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.room_type
