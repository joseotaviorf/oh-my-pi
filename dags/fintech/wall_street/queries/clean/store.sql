SELECT
    id,
    secret,
    description,
    secretHook AS secret_hook
FROM
    datalake_wall_street_raw.store
