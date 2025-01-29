SELECT
    id,
    type                        AS cancellation_type,
    propose,
    origin,
    userinsert                  AS user_insert,
    userupdate                  AS user_update,
    return_value,
    return_value_interest,
    active                      AS is_active,
    created_at                  AS ts_created,
    updated_at                  AS ts_updated,
    request_date                AS ts_requested,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.cancellation

QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
