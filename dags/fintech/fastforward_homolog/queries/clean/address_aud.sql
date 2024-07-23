SELECT
    id,
    rev,
    revtype as rev_type,
    uf as state,
    city,
    complement,
    neighborhood,
    number,
    street
FROM
    datalake_fastforward_homolog_raw.address_aud
