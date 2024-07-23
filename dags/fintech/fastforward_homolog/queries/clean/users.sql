SELECT
    id,
    external_id as id_external,
    name,
    created_at as ts_created,
    updated_at as ts_updated
FROM
    datalake_fastforward_homolog_raw.users
