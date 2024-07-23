SELECT
    id,
    external_id as id_external,
    address_id as id_address,
    cover_image_url,
    created_at as ts_created,
    updated_at as ts_updated
FROM
    datalake_fastforward_homolog_raw.house
