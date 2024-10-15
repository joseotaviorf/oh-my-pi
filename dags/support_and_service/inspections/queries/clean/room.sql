SELECT
    id AS id_room,
    assessment_id AS id_assessment,
    type_id AS id_type,
    uuid,
    name AS room_name,
    comment,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.room
WHERE
	MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
