SELECT
    id AS id_ivr,
    user_id AS id_user,
    user_phone,
    origin,
    strategy,
    requested_at AS ts_requested
FROM
    datalake_bigfone_raw.ivrclosedhistory
