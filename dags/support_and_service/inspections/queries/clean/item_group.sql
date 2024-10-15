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
    datalake_inspections_raw.item_group
WHERE
	MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
