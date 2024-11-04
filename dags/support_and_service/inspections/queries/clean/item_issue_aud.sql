SELECT
    id AS id_item_issue,
    item_id AS id_item,
    type_id AS id_type,
    uuid,
    comment,
    rev,
    revtype,
    revend,
    active AS is_active,
    uuid_mod AS mod_uuid,
    comment_mod AS mod_comment,
    item_mod AS mod_item,
    type_mod AS mod_type,
    active_mod AS mod_is_active,
    created_at_mod AS mod_ts_created,
    updated_at_mod AS mod_ts_updated,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.item_issue_aud
WHERE
	MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
