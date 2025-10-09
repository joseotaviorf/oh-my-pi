SELECT
    id AS id_item_group,
    room_id AS id_room,
    type_id AS id_type,
    main_id AS id_main,
    uuid,
    name,
    comment,
    status,
    is_inferior_quality,
    active_status AS is_active_status,
    active_is_inferior_quality AS is_active_inferior_quality,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspection_services_raw.item_group
