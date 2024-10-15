SELECT
    id as id_contestation_media,
    contestation_id as id_contestation,
    uuid,
    type,
    name,
    created_at as ts_created,
    updated_at as ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.contestation_media
WHERE
	MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
