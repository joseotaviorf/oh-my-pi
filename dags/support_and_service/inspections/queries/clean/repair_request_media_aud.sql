SELECT
    id AS id_repair_request_media,
    repair_request_id AS id_repair_request,
    main_id AS id_main,
    uuid,
    type,
    name,
    rev,
    revtype,
    revend,
    repair_request_id_mod AS mod_id_repair_request,
    main_id_mod AS mod_id_main,
    uuid_mod AS mod_uuid,
    type_mod AS mod_type,
    name_mod AS mod_name,
    repair_request_mod AS mod_repair_request,
    created_at_mod AS mod_ts_created,
    updated_at_mod AS mod_ts_updated,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.repair_request_media_aud
WHERE
	MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
