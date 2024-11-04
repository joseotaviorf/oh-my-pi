SELECT
    id AS id_room,
    assessment_id AS id_assessment,
    type_id AS id_type,
    uuid,
    name AS room_name,
    comment,
    rev,
    revtype,
    revend,
    uuid_mod AS mod_uuid,
    name_mod AS mod_name,
    comment_mod AS mod_comment,
    assessment_mod AS mod_assessment,
    type_mod AS mod_type,
    item_groups_mod AS mod_item_groups,
    created_at_mod AS mod_ts_created,
    updated_at_mod AS mod_ts_updated,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.room_aud
WHERE
	MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
