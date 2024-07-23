SELECT
    id as id_house,
    external_id as id_external,
    address_id as id_address,
    rev,
    revtype as rev_type,
    cover_image_url
FROM
    datalake_fastforward_homolog_raw.house_aud
