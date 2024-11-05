SELECT
    id AS id_review,
    item_id AS id_item,
    user_id AS id_user,
    reviewer_id AS id_reviewer,
    uuid,
    user_type,
    comment,
    rev,
    revtype,
    revend,
    item_id_mod AS mod_id_item,
    user_id_mod AS mod_id_user,
    reviewer_id_mod AS mod_id_reviewer,
    uuid_mod AS mod_uuid,
    user_type_mod AS mod_user_type,
    comment_mod AS mod_comment,
    item_mod AS mod_item,
    review_medias_mod AS mod_review_medias,
    reviewer_mod AS mod_reviewer,
    created_at_mod AS mod_ts_created,
    updated_at_mod AS mod_ts_updated,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.review_aud
WHERE
	MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
