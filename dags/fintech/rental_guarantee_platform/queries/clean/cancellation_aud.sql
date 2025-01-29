SELECT
    id,
    rev,
    revend                      AS rev_end,
    revtype                     AS rev_type,
    type                        AS cancellation_type,
    userinsert                  AS user_insert,
    userupdate                  AS user_update,
    propose,
    origin,
    return_value,
    return_value_interest,
    type_mod                    AS mod_type,
    return_value_interest_mod   AS mod_return_value_interest,
    return_value_mod            AS mod_return_value,
    propose_mod                 AS mod_propose,
    request_date_mod            AS mod_request_date,
    active_mod                  AS mod_active,
    origin_mod                  AS mod_origin,
    active                      AS is_active,
    created_at                  AS ts_created,
    request_date                AS ts_requested
FROM
    datalake_rental_guarantee_platform_raw.cancellation_aud
