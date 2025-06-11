SELECT
    id,
    name,
    email,
    phone,
    created_at as ts_created,
    last_modified_at as ts_last_modified,
    sendbird_id as id_sendbird,
    access_token,
    nickname
FROM
    datalake_linhadireta_test_raw.user
