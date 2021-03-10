SELECT
    id,
    zip,
    state,
    city,
    neighbourhood,
    street_name,
    house_number,
    complement,
    reference,
    lat,
    lng,
    region,
    rev,
    revtype AS rev_type,
    revend AS rev_end
FROM
    datalake_rene_descartes_raw.address_aud