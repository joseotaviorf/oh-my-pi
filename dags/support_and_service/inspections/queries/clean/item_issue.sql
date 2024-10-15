SELECT
    id AS id_item_issue,
    item_id AS id_item,
    type_id AS id_type,
    uuid,
    comment,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.item_issue
WHERE
	MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
