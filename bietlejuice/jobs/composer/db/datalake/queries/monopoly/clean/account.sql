SELECT
    id,
    code,
    name AS account_name,
    created_at AS ts_created
FROM
    datalake_monopoly_raw.account