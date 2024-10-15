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
    datalake_inspections_raw.item_group_type
WHERE
	MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
