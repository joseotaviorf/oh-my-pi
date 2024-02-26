SELECT
    CAST(id AS BIGINT) AS id,
    delinquency AS id_delinquency,
    delinquency_mod AS mod_id_delinquency,
    type AS id_type,
    type_mod AS mod_id_type,
    version,
    userinsert AS id_user_insert,
    userinsert_mod AS mod_id_user_insert,
    userupdate AS id_user_update,
    userupdate_mod AS mod_id_user_update,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.delinquency_cancellation_aud
