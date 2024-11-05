SELECT
    id AS id_review_media,
    review_id AS id_review,
    main_id AS id_main,
    uuid,
    type,
    path,
    rev,
    revtype,
    revend,
    review_id_mod AS mod_id_review,
    main_id_mod AS mod_id_main,
    uuid_mod AS mod_uuid,
    type_mod AS mod_type,
    path_mod AS mod_path,
    review_mod AS mod_review,
    created_at_mod AS mod_ts_created,
    updated_at_mod AS mod_ts_updated,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.review_media_aud
WHERE
	MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
