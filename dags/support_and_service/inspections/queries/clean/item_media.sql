SELECT
    id AS id_item_media,
    item_id AS id_item,
    main_id AS id_main,
    uuid,
    type,
    url,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.item_media
WHERE
	MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
