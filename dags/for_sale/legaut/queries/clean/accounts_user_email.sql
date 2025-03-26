SELECT
    id,
    email,
    name,
    NOW() AS ts_load
FROM
    datalake_legaut_raw.accounts_useremail
