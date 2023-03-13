SELECT
    id,
    country AS country_code,
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
    revend AS rev_end,
    year,
    month,
    day
FROM
    datalake_rene_descartes_raw.address_aud
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id, rev ORDER BY dt DESC) = 1    