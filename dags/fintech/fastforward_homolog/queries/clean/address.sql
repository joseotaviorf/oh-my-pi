SELECT
    id,
    uf as state,
    city,
    complement,
    neighborhood,
    street,
    created_at as ts_created,
    updated_at as ts_updated
FROM
    datalake_fastforward_homolog_raw.address
