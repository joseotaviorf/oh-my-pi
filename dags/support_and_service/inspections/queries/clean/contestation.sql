SELECT
    id AS id_contestation,
    repair_request_id AS id_repair_request,
    reviewer_id AS id_reviewer,
    uuid,
    comment,
    reason,
    origin,
    type,
    cost,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.contestation
WHERE
	MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
