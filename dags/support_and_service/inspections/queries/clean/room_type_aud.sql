SELECT
    id AS id_room_type,
    type,
    order AS number_order,
    deletable AS is_deletable,
    deleted AS is_deleted,
    is_default,
    rev,
    revtype,
    revend,
    type_mod AS mod_type,
    order_mod AS mod_number_order,
    deletable_mod AS mod_is_deletable,
    deleted_mod AS mod_is_deleted,
    is_default_mod AS mod_is_default,
    created_at_mod AS mod_ts_created,
    updated_at_mod AS mod_ts_updated,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.room_type_aud
WHERE
	MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
