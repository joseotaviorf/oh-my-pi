SELECT
    id,
    room_type_id AS id_room_type,
    type,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_inspections_raw.item_group_type